defmodule NodeBucket.Supervisor do
    use Supervisor

    # A simple module attribute that stores the supervisor name
    @name __MODULE__

    @mongo_database Application.get_env(:node_bucket, :mongo_database)
    @mongo_host Application.get_env(:node_bucket, :mongo_host)
    @port Application.get_env(:node_bucket, :port)

    def start_link do
        Supervisor.start_link(__MODULE__, :ok, name: @name)
    end

    def init(:ok) do
        children = [
            supervisor(Task.Supervisor, [[name: NodeBucket.TaskSupervisor]]),
            NodeBucket.Instream.child_spec,
            worker(MongoPool, [[hostname: @mongo_host, database: @mongo_database, max_overflow: 10, size: 5]]),
            worker(Task, [NodeBucket, :accept, [@port]], name: @name)
        ]
        supervise(children, strategy: :one_for_one)
    end
end
