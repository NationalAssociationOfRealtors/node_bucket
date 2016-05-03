defmodule NodeBucket do
    use Application
    require Logger

    def start(_type, _args) do
        NodeBucket.Supervisor.start_link
    end

end
