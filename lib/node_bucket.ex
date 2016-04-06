defmodule NodeBucket do
    use Application
    require Logger

    @key Application.get_env(:node_bucket, :key) <> <<0>>
    @key_map %{"t": "temperature", "h": "humidity", "l": "light", "c": "co2", "v": "voc", "d": "dust", "f": "fuel", "n": "decibel", "r": "rssi", "i": "id" }

    @doc false
    def start(_type, _args) do
        import Supervisor.Spec

        children = [
            supervisor(Task.Supervisor, [[name: NodeBucket.TaskSupervisor]]),
            NodeBucket.Instream.child_spec,
            worker(Task, [NodeBucket, :accept, [Application.get_env(:node_bucket, :port)]]),
            worker(MongoPool, [[database: "lablog"]])
        ]

        opts = [strategy: :one_for_one, name: NodeBucket.Supervisor]
        Supervisor.start_link(children, opts)
    end

    @doc """
    Starts accepting connections on the given `port`.
    """
    def accept(port) do
        {:ok, socket} = :gen_udp.open(port, [:binary, reuseaddr: true, ip: {0,0,0,0}])
        Logger.info "Accepting connections on 0.0.0.0:#{port}"
        handle(socket)
    end

    def handle(socket) do
        receive do
            {udp, client_socket, client_addr, client_port, data} ->
                {:ok, pid} = Task.Supervisor.start_child(NodeBucket.TaskSupervisor, fn ->
                    process(client_socket, client_addr, client_port, data)
                end)
                handle(socket)
            error ->
                Logger.info "Other #{error}"
                handle(socket)
        end
    end

    def process(socket, addr, port, data) do
        message = data |> decrypt |> deserialize |> write
    end

    def decrypt(data) when data |> is_binary do
        << iv :: binary-size(16), message :: binary >> = data
        [t, _] = :crypto.block_decrypt(:aes_cbc128, @key, iv, message) |> :binary.split(<<0>>)
        t
    end

    def deserialize(message) when message |> is_binary do
        message |> Poison.Parser.parse!
    end

    def write(message) when message |> is_map do
        {interface, m} = message |> Map.pop("i")
        node = get_node(interface)
        case message |> map_keys(node, interface) |> NodeBucket.Instream.write do
            :ok ->
                Logger.info update_node(node)
        end
    end

    def map_keys(message, node, interface) do
        %{database: "lablog", points: message
            |> Map.keys
            |> Enum.map(fn(x) ->
                key = Map.get(@key_map, String.to_atom(x))
                %{
                    measurement: "node.#{key}",
                    fields: %{
                        value: Map.get(message, x)
                    },
                    tags: %{
                        node: node.value,
                        interface: interface
                    }
                }
            end)}
    end

    def get_node(interface) do
        cursor = Mongo.find(MongoPool, "interfaces", %{"id" => interface}, limit: 1)
        record = Enum.to_list(cursor) |> List.first
        record["_id"]
    end

    def update_node(node) do
        now = :erlang.system_time(:milli_seconds)
        case Mongo.update_one(MongoPool, "interfaces", %{"_id": node}, %{"$set": %{"_last_run": %BSON.DateTime{utc: now}}}) do
            {:ok, _ } ->
                :ok
        end
    end

end
