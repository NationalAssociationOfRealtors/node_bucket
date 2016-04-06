defmodule NodeSeries do
    use Instream.Series
    key = nil
    series do
        database "lablog"
        measurement "node.#{key}"

        tag :node
        tag :interface

        field :value
    end
end
