require 'active_record'
require 'request_store'
require_relative './venture/config'
require_relative './venture/events'
require_relative './venture/errors'
require_relative './venture/migrate'
require_relative './venture/success'

module Venture
  extend self
  extend Forwardable

  def_delegators Config, :event_base_class, :valid_event_class?

  def as_event!(base_params: {}, fail_as: default_error_event_class)
    if !base_params.is_a?(Hash)
      raise ArgumentError, "base params should be a hash"
    end

    if !valid_event_class?(fail_as)
      raise ArgumentError, "#{fail_as} is not a valid event class"
    end

    if !block_given?
      raise ArgumentError, "What do you want to happen?"
    end

    begin
      events_created = ActiveRecord::Base.transaction(requires_new: true) do
        # call the event block, expecting an instance of Venture::Success
        # on return.
        #
        # when nesting calls to as_event, we need to wait for the outermost block
        # to finish and close the transaction, otherwise we may, e.g., dispatch
        # Sidekiq workers to work on ids that don't exist yet. before calling the
        # block, we push a small string token onto a thread-local stack, and pop
        # it off again when we're done. that way, we can check the size of that
        # stack later when then transaction finishes; if it's empty, we know we
        # were the outermost as_event on the call stack, and we can run the side
        # effects for all the nested calls, which we return on Venture::Success
        # objects and store in a thread-local array.
        #
        # the only reason to use a token here (instead of, say, nil) is the remote
        # possibility of non-local returns, say from a throw or raise that happens
        # at stack depth N, blows away one or more nested as_event frames on the
        # stack, and is then caught somewhere higher up; in that case, if we
        # were just counting the stack, effects would never fire because the
        # stack would never empty. we use a short token to make sure we're popping the
        # same marker we pushed. if they don't match, there was a non-local return, and
        # we'll raise an error. (we could in theory support this somehow but for now
        # the moral of the story is... don't do that)

        pushed_token = push_token(make_stack_token)

        begin
          success = yield
        ensure
          popped_token = pop_token
        end

        if !success.is_a?(Success)
          raise Errors::ReturnError,
            "service block must return an instance of Venture::Success"
        end

        if pushed_token != popped_token
          raise Errors::ReturnError,
            "There was a non-local return in your nested calls to as_event!, help!"
        end

        # capture the recorded events as they are created so we
        # can return them
        created_events = []

        # separate begin block here to distinguish failures
        # in the actual update from a failure in creating the
        # success event
        begin
          create_event_list!(success.events, base_params, created_events)
        rescue => e
          ActiveRecord::Base.logger.error("Operation succeeded but can't create event, rolling back")
          raise
        end

        queue_success(success)

        # return the newly created events, but fresh from the database
        event_base_class.where(id: created_events.map(&:id)).to_a
      end

      # note we are intentionally rescuing from Exception here rather than StandardError
      # because we need to reset the nested state if the thread is reused, and if it's
      # not reused, it doesn't matter. (and we are in no position to say whether it will
      # be reused.) open to other perspectives but this seems correct.
    rescue Exception => e
      clear_nested_state

      if e.is_a?(Errors::EventError)
        # these exceptions provide a failure event of their own, allowing callers to
        # specify one or more failure event types other than the one passed in by
        # the call to as_event! which is useful when you only know what the failure
        # event should be once it happens
        ActiveRecord::Base.logger.error("#{e.class.event}: #{e.message}")

        # on failures, the .params method is called with the passed in base_params and the
        # exception encountered
        e.created_events << create_event!(
          e.class.event,
          base_params.merge(e.params),
          error: e
        )
        # create any additional events indicated at runtime
        create_event_list!(e.additional_events, base_params, e.created_events)

      elsif e.is_a?(StandardError)
        # other failures, where we record the default failure event given in the call
        # to as_event!
        ActiveRecord::Base.logger.error("#{fail_as}: #{e.message}")
        create_event!(fail_as, base_params, error: e)

      else
        # For non-standard error such as a memory error or keyboard interrupt
        # we don't want log anything else or save anything to the database
        # just clear the nested state and then re-raise
      end

      raise
    end

    # now that our transaction has completed, see if we're the outermost one; if so,
    # run any deferred effects
    if stack_size == 0
      this_success_queue = success_queue
      clear_nested_state
      this_success_queue.each { |success| call_effects!(success) }
    end

    # return the events created by the transaction block
    events_created
  end

  private

  def create_event!(event_class, params, error: nil)
    if error
      if !error.is_a?(StandardError)
        raise ArgumentError, "#{error} is not a valid error type"
      end

      params.merge!(error_message: error.message, error_type: error.class)
    end

    params.merge!(event_class.params(params))

    event_class.create!(params)
  end

  def create_event_list!(event_param_list, base_params, created_events = [])
    event_param_list.each_with_object([]) do |(success_event_class, returned_params_list), recorded_events|
      if !valid_event_class?(success_event_class)
        raise ArgumentError, "#{success_event_class} is not a valid event class"
      end

      # unfortunately Array(...) doesn't work here as it turns hashes
      # into arrays
      returned_params_list = if returned_params_list.is_a?(Array)
                               returned_params_list
                             else
                               [returned_params_list]
                             end

      returned_params_list.each do |returned_params|
        if !returned_params.is_a?(Hash)
          raise ArgumentError, "returned params is not hash: #{returned_params}"
        end

        created_events << create_event!(
          success_event_class,
          base_params.merge(returned_params)
        )
      end

      created_events
    end
  end

  def call_effects!(success, events_created, base_params)
    success.events&.call(events_created)
  rescue => e
    create_event!(EffectsErrorEvent, base_params, error: e)
  end

  def make_stack_token; rand(36**8).to_s(36); end

  def event_stack; RequestStore.store[:_event_service_stack] ||= []; end

  def stack_size; event_stack.size; end

  def push_token(token); event_stack.push(token) && token; end

  def pop_token; event_stack.pop; end

  def success_queue; RequestStore.store[:_event_service_queue] ||= []; end

  def queue_success(success); success_queue << success; end

  def clear_nested_state
    RequestStore.store[:_event_service_stack] = []
    RequestStore.store[:_event_service_queue] = []
  end
end
