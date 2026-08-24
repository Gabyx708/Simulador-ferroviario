using SimuladorFerrocarril.Domain.Core;

namespace SimuladorFerrocarril.Domain.Lines;

public class LineStation : Entity<Guid>
{
    public Guid StationId { get; private set; }

    public int Order { get; private set; }

    public LineStation(
        Guid id,
        Guid stationId,
        int order)
        : base(id)
    {
        if (stationId == Guid.Empty)
            throw new DomainException(
                "Station ID cannot be empty.");

        if (order < 0)
            throw new DomainException(
                "Station order cannot be negative.");

        StationId = stationId;
        Order = order;
    }

    protected LineStation()
    {
    }
}