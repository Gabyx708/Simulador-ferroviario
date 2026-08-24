using SimuladorFerrocarril.Domain.Core;

namespace SimuladorFerrocarril.Domain.Lines;

public class Line : AggregateRoot<Guid>
{
    private readonly List<LineStation> _stations = new();

    public string Name { get; private set; }

    public string Code { get; private set; }

    public IReadOnlyCollection<LineStation> Stations =>
        _stations.AsReadOnly();

    public Line(
        Guid id,
        string name,
        string code)
        : base(id)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException(
                "Line name cannot be empty.");

        if (string.IsNullOrWhiteSpace(code))
            throw new DomainException(
                "Line code cannot be empty.");

        Name = name;
        Code = code;
    }

    protected Line()
    {
        Name = null!;
        Code = null!;
    }

    public void AddStation(LineStation station)
    {
        ArgumentNullException.ThrowIfNull(station);

        if (_stations.Any(x => x.StationId == station.StationId))
            throw new DomainException(
                "Station already belongs to the line.");

        if (_stations.Any(x => x.Order == station.Order))
            throw new DomainException(
                "Another station already has this order.");

        _stations.Add(station);

        _stations.Sort(
            (a, b) => a.Order.CompareTo(b.Order));
    }

    public void RemoveStation(Guid stationId)
    {
        var station = _stations
            .FirstOrDefault(x => x.StationId == stationId);

        if (station is null)
            throw new DomainException(
                "Station does not belong to the line.");

        _stations.Remove(station);
    }
}