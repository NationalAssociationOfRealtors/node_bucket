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
        {:ok, socket} = :gen_udp.open(port, [:binary, {:active, :true}])
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
        IO.inspect addr
        IO.inspect port
        :ok = data
            |> decrypt
            |> deserialize
            |> write
            |> ack(socket, addr, port)
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
        points = m
            |> map_keys(node, interface)
            |> IO.inspect
        :ok = NodeBucket.Instream.write(points)
        update_interface(interface)
    end

    def ack(:ok, socket, address, port) do
        :gen_udp.send(socket, address, port, "1")
    end

    def map_keys(message, node, interface) do
        %{database: @influx_database, points: message
            |> Map.keys
            |> Enum.map(fn(x) ->
                key = Map.get(@key_map, String.to_atom(x))
                %{
                    measurement: "node.#{key}",
                    fields: %{
                        value: Map.get(message, x) / 1
                    },
                    tags: %{
                        node: node,
                        interface: Base.encode16(interface.value, case: :lower)
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
        {:ok, _} = Mongo.update_one(
            MongoPool,
            "interfaces",
            %{"_id": interface},
            %{"$set": %{"_last_run": %BSON.DateTime{utc: now}}}
        )
        :ok
    end

end
