using SimuladorFerrocarril.Domain.Core;

namespace SimuladorFerrocarril.Domain.Trains;

public class Train : AggregateRoot<Guid>
{
    public string Name { get; private set; }

    public string Code { get; private set; }


    public TrainStatus Status { get; private set; }

    public Train(
        Guid id,
        string name,
        string code)
        : base(id)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException("Train name cannot be empty.");

        if (string.IsNullOrWhiteSpace(code))
            throw new DomainException("Train code cannot be empty.");

        Name = name;
        Code = code;
        Status = TrainStatus.Stopped;
    }

    protected Train()
    {
        Name = null!;
        Code = null!;
    }

    public void StartService()
    {
        if (Status == TrainStatus.OutOfService)
            throw new DomainException(
                "An out-of-service train cannot start service.");

        if (Status == TrainStatus.Cancelled)
            throw new DomainException(
                "A cancelled train cannot start service.");

        Status = TrainStatus.InService;
    }

    public void Delay()
    {
        if (Status != TrainStatus.InService)
            throw new DomainException(
                "Only a train in service can be delayed.");

        Status = TrainStatus.Delayed;
    }

    public void ResumeService()
    {
        if (Status != TrainStatus.Delayed)
            throw new DomainException(
                "Only a delayed train can resume service.");

        Status = TrainStatus.InService;
    }

    public void Cancel()
    {
        Status = TrainStatus.Cancelled;
    }

    public void RemoveFromService()
    {
        Status = TrainStatus.OutOfService;
    }
}