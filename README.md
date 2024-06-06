# Venture: an event architecture for Rails

## Todo

- Error handling in effect blocks

## About

This gem provides a framework for service-layer code in Ruby apps backed by databases. It implements the following, in ascending order of perverse implications:

- Services either complete successfully or raise; i.e., every service call is a bang method
- On success, one or more events are recorded indicating what happens, and on failure, one or more events are created indicating what went wrong
- Every service call implies a database transaction
- Side effects of successful operations should be deferred until after the transaction closes
- Services are composable; i.e., you can nest calls without all hell breaking loose

## What?

Suppose we want (among other things) an event recorded every time a `Thing` is created:

```ruby
class ThingService
  class ThingCreated < Venture::Event; end
  class ThingError < Venture::ErrorEvent; end

  def create_the_thing!(thing_params)
    Venture.as_event!(fail_as: ThingError) do
      thing = Thing.create!(thing_params)

      Venture::Success.new(
        events: ThingCreated => {thing_id: thing.id},
        effects: ->(events) do
          subject = "thing #{thing.id} was created at #{events.first.created_at}")
          ThingCreationMailer.deliver(subject:)
        end
      )
    end 
  end
end
```

We call `as_event!`, with an optional error type to fail as (more
on this shortly), and a block for our application logic. That block
will be run in a database transaction, and must meet its end in one
of two ways:

- raise an exception
- return an instance of `Venture::Success`, along with specifications for events to be recorded and effects to be run

....

In case of success, `as_event!` will record any events indicated,
then check to see if it's executing inside another call to `as_event!`.
If so, it will queue any effects for execution after the outermost
call returns, the close its database transaction and return to its
caller. If this is the outermost call to `as_event!` it closes its
transaction, commiting the changes to the database, and runs any
queued effects. In this way, simple services can be composed into
larger actions that are atomic with respect to the database, and the
effects requested by early successes in a complex action can be
canceled by later failures.

In case of an exception, `as_event!` will record the error events specified
by the failing block, roll back the database, and reraise the exception.

## Why?

This is as much an approach to structuring code as it as a gem for
recording events. Rails is famously opinionated, but in practice
doesn't provide much guidance for how application logic should be
invoked, or what callers should expect. As applications grow,
symptoms of that vacuum often include controllers being slimmed
down into thicker models, followed by the creation of some kind of
service layer once functionality stops corresponding one-to-one
with model classes.  (I'm using "service layer" in the Martin Fowler
sense of modules that "[establish] a set of available operations
and [coordinate] the application's response in each operation."
"Service objects" are one way to approach that but not the only
way.)

The need to organize this layer efficiently is compounded by the
need to not repeat ourselves: DRY code pretty much implies
composability. If your application lets developers `order_a_tuna_sandwich!`
and `order_a_blt!`, it's only a matter of time before you need to
let them `order_a_tuna_sandwich_and_a_blt!`. The problem of composition
is that if each of these operations is truly self-contained, and
you run out of bacon, you've already charged the customer for the
tuna, when what you need to do is roll back the entire order.  The
service layer needs to be able to specify things that happen only
in the case of total success, like charging the customer---we'll
call those "effects." Other examples include sending emails, queuing
Sidekiq jobs, and so on. In order for service layer actions to be
truly composable, they have to be able to defer those effects until
an entire _composed_ operation succeeds, not just until after its
own `as_event!` block exits succesfully. Developers should not be forced
to reckon with this every time they add a module to the service
layer. Instead, the service layer can abstract this functionality,
providing consistent conventions and enforced behavior across the
entire application.

This gem was extracted from an application for certifying state
employees for work like rideshare driving or child care, where a
statutory certification is made by an application process, and must
be kept current by reapplying regularly, say once a year. (Apologies
for overloading the word "application.") Among other requirements,
employees should have at most one currrent application, and state
agencies should be able to make new applications for employees at
will. That implies a couple things:

- If an agency creates a new application for an employee who already has one,
the existing application should be closed in favor of the new one
- If an error occurs in the process of creating the new application, _or_ in the
process of closing the old one, an error should be recorded but no other changes
should be committed

Let's start with the method to close an existing application:

```ruby
module EmployeeCertificationService
  extend self

  def close_application!(employee_application_id)
    Venture.as_event!(
      base_params: { employee_application_id: },
      fail_as: CloseEmployeeApplicationError
    ) do
      EmployeeApplication.find(employee_application_id).close!

      Venture::Success.new(
        events: EmployeeApplicationClosed => {}
        effects: ->(events) do
          Rails.logger.info("closed app id #{events.first.employee_application_id}")
        end
      )
    end
  end
```

The arguments to `as_event!` are:

- `base_params`: a hash of params that will be passed to any event recorded, on
  success or failure
- `fail_as`: If an exception is raised, and no more specific error event is given, record
  an event that is an instance of the class given here
- the block: A block for your application code, wrapped in a database transaction

The application code should either raise an exception, or return an instance of `Venture::Success` with the following options possibly specified:

- `events`: One or more events to record. The format here is a hash
whose keys are event classes, and whose values are hashes of event
params, or arrays thereof. These will be merged onto the base params
before creation. Why?  Because (I submit) callers should have the
details of event creation encapsulated for them. This format may
not be idiomatic, but it is declarative. If you don't like it, you
can just create events imperatively in your application code instead. (Just
remember to merge your base params first.)
- `effects`: A lambda to be run on success, which can dispatch those
things like log messages, confirmation emails, Sidekiq jobs, etc.
which should only be dispatched if everything succeeds. Because it
is also a closure, you have access to all of the local state built
up in your application logic.

Both of these are optional, and you may return a bare instance of
`Venture::Success` if you want (say, if you prefer to record events
yourself imperatively).

Now let's look at how this can be composed into a larger action:

```
  def create_application!(employee_id)
    Venture.as_event!(
      base_params: { employee_id: },
      fail_as: EmployeeCertificationError
    ) do
      employee = Employee.find(employee_id)

      if employee.current_application
        close_application!(employee.current_application.id)
      end
      
      EmployeeApplication.create!(employee_id:)
      
      Venture::Success.new(
        events: EmployeeApplicationCreated => {},
        effects: ->(events) do
          Rails.logger.info("created new app id #{events.first.employee_application_id}")

          # queue up some background jobs to email the user and handle the new application
          NewAppConfirmationEmailWorker.perform_async(events.first.employee_id)
          BeginCertificationWorker.perform_async(events.first.employee_application_id)
        end
      end
    end 
  end
```

In this method, we create a new application for the indicated employee, but first we
check if they have a current application, and if so, we close it by calling our
service method above. If everything runs successfully, the employee's old application
will be closed, a new one will be created, two log messages will go out, and the
background workers will be called. If either step fails, in either order, the employee
will be left with their original application, the appropriate error event(s) will be
recorded, and the exception causing the failure will be reraised. No `effects` lambdas
will be executed.

The original imperative from the client was to record significant
application events in the database. The concerns above don't relate
directly to that task, but they have to be sorted out if the `events`
table is going to be used as an audit trail, at least if the service
layer is also composable. The alternatives would be some combination of
complex service actions not executing atomically, (bad) manual
rollback code at the application level (also bad) and/or a risk of the event log
becoming polluted by events that didn't actually "happen" because they
were rolled back (definitely bad). We don't want any of those things.

## Alternatives and prior art

Folks here at [Gnar](https://thegnar.co/) are fans of the Interactor
gem, and I looked at that initially for our needs. It imposes some
nice structure on the no-person's-land between controllers and
models, which is valuable in and of itselef, and can accommodate
database transactions using its `around` hook. It has `Organizer`
for composing smaller actions into largers ones. But it provides
no way to defer effects, much less any way to tie those effects to
the closing of a database transaction. Interactor has no real concept
of the database at all, as it operates at a higher level of
abstraction; our original goal here was a reliable database log of
a complex application, so it's not surprising it didn't quite line
up. I also prefer declarative interfaces to things having to imperatively
`fail!` a context, and to not have to draw a categorical distinction
between simple (`Interactor`) and complex (`Organizer`) actions, but those
last two are pretty subjective.

That said: Venture and Interactor probably go really well together! If you use
Interactor to structure the interface you provide to callers, and use Venture 
for event creation and service composition (sorry `Organizer`) it will almost
certainly be great. Test app forthcoming!
