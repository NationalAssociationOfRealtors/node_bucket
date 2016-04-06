defmodule NodeBucket do
    use Application
    require Logger

    @doc false
    def start(_type, _args) do
        import Supervisor.Spec

        children = [
            supervisor(Task.Supervisor, [[name: NodeBucket.TaskSupervisor]]),
            worker(Task, [NodeBucket, :accept, [Application.get_env(:node_bucket, :port)]])
        ]

        opts = [strategy: :one_for_one, name: NodeBucket.Supervisor]
        Supervisor.start_link(children, opts)
    end

    @doc """
    Starts accepting connections on the given `port`.
    """
    def accept(port) do
        {:ok, socket} = :gen_udp.open(port, [reuseaddr: true])
        Logger.info "Accepting connections on port #{port}"
        handle(socket)
    end

    def handle(socket) do
        receive do
            {udp, client_socket, client_addr, client_port, data} ->
                # create dynamic workers to process datagrams
                {:ok, pid} = Task.Supervisor.start_child(NodeBucket.TaskSupervisor, fn -> process(client_socket, client_addr, client_port, data) end)
                #process(client_socket, client_addr, client_port, data) Not scalable!!
                handle(socket)
            {other, _, _, _} ->
                Logger.info "Other #{other}"
                handle(socket)
        end
    end

    def process(socket, addr, port, data) do
        Logger.info "#{data}"
    end

end
