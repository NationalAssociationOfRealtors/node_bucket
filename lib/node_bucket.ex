defmodule NodeBucket do
    use Application
    require Logger

    @name __MODULE__

    @cipher_key Application.get_env(:node_bucket, :cipher_key) <> <<0>>

    @influx_database Application.get_env(:node_bucket, :influx_database)

    @key_map %{
        "t": "temperature",
        "h": "humidity",
        "l": "light",
        "c": "co2",
        "v": "voc",
        "d": "dust",
        "f": "fuel",
        "n": "decibel",
        "r": "rssi",
        "i": "id"
    }

    def start(_type, _args) do
        NodeBucket.Supervisor.start_link
    end

    def accept(port) do
        {:ok, socket} = :gen_udp.open(port, [:binary, reuseaddr: true, ip: {0,0,0,0}])
        Logger.info "Accepting datagrams on port:#{port}"
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
        Logger.info data |> decrypt |> deserialize |> write
    end

    def decrypt(data) when data |> is_binary do
        << iv :: binary-size(16), message :: binary >> = data
        :crypto.block_decrypt(:aes_cbc128, @cipher_key, iv, message) |> :binary.split(<<0>>) |> List.first
    end

    def deserialize(message) when message |> is_binary do
        message |> Poison.Parser.parse!
    end

    def write(message) when message |> is_map do
        {node, m} = message |> Map.pop("i")
        interface = get_interface(node)
        points = m |> map_keys(node, interface)
        IO.inspect points
        case points |> NodeBucket.Instream.write do
            :ok ->
                update_interface(interface)
        end
    end

    def map_keys(message, node, interface) do
        %{database: @influx_database, points: message
            |> Map.keys
            |> Enum.map(fn(x) ->
                key = Map.get(@key_map, String.to_atom(x))
                %{
                    measurement: "node.#{key}",
                    fields: %{
                        value: Map.get(message, x)
                    },
                    tags: %{
                        node: node,
                        interface: interface.value
                    }
                }
            end)}
    end

    def get_interface(node) do
        cursor = Mongo.find(MongoPool, "interfaces", %{"id" => node}, limit: 1)
        record = Enum.to_list(cursor) |> List.first |> Map.get("_id")
    end

    def update_interface(interface) do
        now = :erlang.system_time(:milli_seconds)
        case Mongo.update_one(MongoPool, "interfaces", %{"_id": interface}, %{"$set": %{"_last_run": %BSON.DateTime{utc: now}}}) do
            {:ok, _ } ->
                :ok
        end
    end

end
