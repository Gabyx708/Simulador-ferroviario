using SimuladorFerrocarril.Domain.Core;

namespace SimuladorFerrocarril.Domain.Trips;

public class Trip : AggregateRoot<Guid>
{
    public Guid TrainId { get; private set; }

    public Guid LineId { get; private set; }

    public DateTime ScheduledDeparture { get; private set; }

    public DateTime ScheduledArrival { get; private set; }

    public DateTime? ActualDeparture { get; private set; }

    public DateTime? ActualArrival { get; private set; }

    public TripStatus Status { get; private set; }

    public Trip(
        Guid id,
        Guid trainId,
        Guid lineId,
        DateTime scheduledDeparture,
        DateTime scheduledArrival)
        : base(id)
    {
        if (trainId == Guid.Empty)
            throw new DomainException(
                "Train ID cannot be empty.");

        if (lineId == Guid.Empty)
            throw new DomainException(
                "Line ID cannot be empty.");

        if (scheduledArrival <= scheduledDeparture)
            throw new DomainException(
                "Scheduled arrival must be after scheduled departure.");

        TrainId = trainId;
        LineId = lineId;
        ScheduledDeparture = scheduledDeparture;
        ScheduledArrival = scheduledArrival;
        Status = TripStatus.Scheduled;
    }

    protected Trip()
    {
    }

    public void Start(DateTime departureTime)
    {
        if (Status != TripStatus.Scheduled &&
            Status != TripStatus.Delayed)
        {
            throw new DomainException(
                "Trip cannot be started in its current state.");
        }

        ActualDeparture = departureTime;
        Status = departureTime > ScheduledDeparture
            ? TripStatus.Delayed
            : TripStatus.InProgress;
    }

    public void Complete(DateTime arrivalTime)
    {
        if (Status != TripStatus.InProgress &&
            Status != TripStatus.Delayed)
        {
            throw new DomainException(
                "Only an active trip can be completed.");
        }

        if (ActualDeparture.HasValue &&
            arrivalTime <= ActualDeparture.Value)
        {
            throw new DomainException(
                "Arrival time must be after departure time.");
        }

        ActualArrival = arrivalTime;
        Status = TripStatus.Completed;
    }

    public void Delay()
    {
        if (Status != TripStatus.Scheduled &&
            Status != TripStatus.InProgress)
        {
            throw new DomainException(
                "Trip cannot be delayed in its current state.");
        }

        Status = TripStatus.Delayed;
    }

    public void Cancel()
    {
        if (Status == TripStatus.Completed)
            throw new DomainException(
                "A completed trip cannot be cancelled.");

        Status = TripStatus.Cancelled;
    }
}