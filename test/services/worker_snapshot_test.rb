require "test_helper"

class WorkerSnapshotTest < ActiveSupport::TestCase
  test "reports queue metrics and registered processes" do
    queue = Module.new
    { ReadyExecution: 4, ScheduledExecution: 2, ClaimedExecution: 1, FailedExecution: 3 }.each do |name, count|
      queue.const_set(name, Struct.new(:count).new(count))
    end
    processes = Object.new
    processes.define_singleton_method(:order) { |**| self }
    processes.define_singleton_method(:limit) { |_| [] }
    queue.const_set(:Process, processes)
    snapshot = WorkerSnapshot.call(adapter: "SolidQueue", queue: queue)
    assert snapshot[:available]
    assert_equal [ 4, 2, 1, 3 ], snapshot[:counts].values
    assert_empty snapshot[:processes]
  end

  test "connection failures are shown as unavailable rather than zero workers" do
    queue = Module.new
    broken_model = Object.new
    broken_model.define_singleton_method(:count) { raise ActiveRecord::ConnectionNotEstablished }
    queue.const_set(:ReadyExecution, broken_model)
    snapshot = WorkerSnapshot.call(adapter: "SolidQueue", queue: queue)
    assert_not snapshot[:available]
    assert_match(/Não foi possível/, snapshot[:message])
  end
end
