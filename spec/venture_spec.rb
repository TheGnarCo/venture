require "spec_helper"

RSpec.describe Venture do
  describe "as_event!" do
    context "operation is successful" do
      before(:all) do
        Venture.as_event!(base_params: { name: "my event" }) do
          Venture::Spec::Widget.create!(name: "my widget")
          Venture::Success.new(events: { 
            Venture::Spec::Events::TestOkEvent => {} 
          })
        end
      end

      after(:all) { clear_db }

      it "runs the block" do
        expect(Venture::Spec::Widget.last.name).to eq("my widget")
      end

      it "records success event" do
        expect(Venture::Spec::Events::TestOkEvent.count).to eq(1)
      end

      it "updates params on success" do
        expect(Venture::Spec::Events::TestOkEvent.first.params["name"]).to eq("my event")
      end
    end

    context "operation is successful with deferred side effects" do
      it "runs effects after transaction is closed, from inner to outer nesting" do
        log = []

        Venture.as_event! do
          log << "outer"

          Venture.as_event! do
            log << "inner-a"

            Venture::Success.new(
              effects: ->(_events) do
                expect(log).to eq(["outer", "inner-a", "inner-b"])
                log << "inner-a effect"
              end
            )
          end

          Venture.as_event! do
            log << "inner-b"

            Venture::Success.new(
              effects: ->(_events) do
                expect(log).to eq(["outer", "inner-a", "inner-b", "inner-a effect"])
                log << "inner-b effect"
              end
            )
          end

          Venture::Success.new(
            effects: ->(_events) do
              expect(log).to eq(["outer", "inner-a", "inner-b", "inner-a effect", "inner-b effect"])
              log << "outer effect"
            end
          )
        end

        expect(log).to eq(["outer", "inner-a", "inner-b", "inner-a effect", "inner-b effect", "outer effect"])
      end
    end

    context "operation with deferred side effects is not successful" do
      before(:each) do
        # Not that this does NOT inherit from StandardError
        stub_const("NonStandardException", Class.new(Exception))
      end

      it "runs effects after transaction is closed, from inner to outer nesting" do
        log = []

        begin
          Venture.as_event! do
            log << "outer"

            Venture.as_event! do
              log << "inner-a"

              Venture::Success.new(
                effects: ->(_events) do
                  raise RuntimeError, "this inner-a callback should not execute after another exception was raised"
                  log << "inner-a effect"
                end
              )
            end

            Venture.as_event! do
              log << "inner-b"

              Venture::Success.new(
                effects: ->(_events) do
                  raise RuntimeError, "this inner-b callback should not execute after another exception was raised"
                  log << "inner-b effect"
                end
              )
            end

            Venture.as_event! do
              log << "inner-c"
              raise NonStandardException
            end

            Venture::Success.new(
              effects: ->(_events) do
                log << "outer effect"
              end
            )
          end
        rescue NonStandardException
        end

        expect(log).to eq(["outer", "inner-a", "inner-b", "inner-c"])
      end
    end

    context "operation is successful with multiple success events" do
      before(:each) do
        stub_const('TestOkEvent2', Class.new(Event) do
          def self.params(params)
            params.merge(validation_message: "success too")
          end
        end)
      end

      let (:widget) { Widget.create!(name: "first widget") }
      let! (:block_return) {
        Venture.as_event!(
          base_params: {},
        ) do
          widget2 = Widget.create!(name: "second widget")

          Venture::Success.new(
            events: {
              TestOkEvent => {widget_id: widget.id},
              TestOkEvent2 => {widget_id: widget2.id}
            }
          )
        end
      }

      it "records multiple success events" do
        expect(TestOkEvent.count).to eq(1)
        expect(TestOkEvent2.count).to eq(1)
      end

      it "records per-event type params" do
        expect(TestOkEvent.first.params["validation_message"]).to eq("success")
        expect(TestOkEvent2.first.params["validation_message"]).to eq("success too")
      end
    end

    context "operation raises an error with default failure event" do
      let (:widget) { Widget.create!(name: "first widget") }

      let! (:block_return) {
        begin
          Venture.as_event!(
            base_params: { widget_id: widget.id }
          ) do
            Widget.create!(name: "created in block")
            raise "boom!"
          end
        rescue => e
          e
        end
      }

      it "rolls back the changes" do
        expect(Widget.last.name).to eq("first widget")
      end

      it "reraises the exception" do
        expect(block_return).to be_a(RuntimeError)
        expect(block_return.message).to eq("boom!")
      end

      it "records error event of the default type" do
        expect(Venture::Events::ErrorEvent.count).to eq(1)
      end

      it "preserves exception type and message on default failure event" do
        event = Venture::Events::ErrorEvent.first

        expect(event.params["error_message"]).to eq("boom!")
        expect(event.params["error_type"]).to eq("RuntimeError")
      end
    end

    context "operation raises an error with specified failure event" do
      let (:widget) { Widget.create!(name: "first widget") }
      let! (:block_return) {
        begin
          Venture.as_event!(
            base_params: { widget_id: widget.id },
            fail_as: TestFailureEvent,
          ) do
            Widget.create!(name: "created in block")
            raise "boom!"
          end
        rescue => e
          e
        end
      }

      it "reraises the exception" do
        expect(block_return).to be_a(RuntimeError)
        expect(block_return.message).to eq("boom!")
      end

      it "records error event of a specified type" do
        expect(TestFailureEvent.count).to eq(1)
      end

      it "updates params on failure" do
        expect(TestFailureEvent.first.params["validation_message"]).to eq("failure")
      end

      it "preserves exception type and message on default failure event" do
        event = TestFailureEvent.first

        expect(event.params["error_message"]).to eq("boom!")
        expect(event.params["error_type"]).to eq("RuntimeError")
      end
    end

    context "operation raises an EventError" do
      let (:widget) { Widget.create!(name: "first widget") }
      let! (:block_return) {
        begin
          Venture.as_event!(
            base_params: { widget_id: widget.id }
          ) do
            Widget.create!(name: "created in block")
            raise TestEventError.new(
              "boom!",
              remote_status_code: 404,
              remote_status_text: 'not found'
            )
          end
        rescue => e
          e
        end
      }

      it "passes parameters into the event record" do
        event = TestFailureEvent.first
        expect(event.params["remote_status_code"]).to eq(404)
        expect(event.params["remote_status_text"]).to eq('not found')
      end

      it "reraises the exception" do
        expect(block_return).to be_a(TestEventError)
        expect(block_return.message).to eq("boom!")
      end

      it "records the error type specified by the exception" do
        expect(TestFailureEvent.count).to eq(1)
      end

      it "updates params on failure" do
        expect(TestFailureEvent.first.params["validation_message"]).to eq("failure")
      end

      it "preserves exception type and message on default failure event" do
        event = TestFailureEvent.first

        expect(event.params["error_message"]).to eq("boom!")
        expect(event.params["error_type"]).to eq("Venture::Spec::Errors::TestEventError")
      end
    end

    context "operation is composite" do
      it "allows successful inner event blocks to record success events" do
        expect do
          Venture.as_event! do
            Venture.as_event! do
              widget = Widget.create!(name: "created in block")
              Venture::Success.new(
                events: { TestOkEvent => { widget_id: widget.id } }
              )
            end

            Venture::Success.new
          end
        end.to change { TestOkEvent.count }.by(1)

        event = TestOkEvent.last
        expect(Widget.find(event.params["widget_id"]).name).to eq('created in block')
      end

      it "allows failed inner event blocks to record failure events" do
        error_uuid = SecureRandom.hex
        old_event_count = TestFailureEvent.count
        old_widget_count = Widget.count

        begin
          Venture.as_event! do
            Venture.as_event! do
              widget = Widget.create!(name: "created in block")
              raise TestEventError.new "error in inner block", error_uuid: error_uuid
            end
            Venture::Success.new
          end
        rescue TestEventError
        end

        expect(Widget.count).to eq(old_widget_count)
        expect(TestFailureEvent.count).to eq(old_event_count + 1)
        expect(Widget.where(name: "created in block")).to be_empty

        event = TestFailureEvent.last
        expect(event.params["error_uuid"]).to eq(error_uuid)
        expect(event.params["error_message"]).to eq("error in inner block")
      end
    end
  end
end
