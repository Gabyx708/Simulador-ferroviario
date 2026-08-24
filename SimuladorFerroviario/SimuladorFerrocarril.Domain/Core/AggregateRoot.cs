namespace SimuladorFerrocarril.Domain.Core;

public abstract class AggregateRoot<TId> : Entity<TId>
{
    protected AggregateRoot(TId id)
        : base(id)
    {
    }

    protected AggregateRoot()
    {
    }
}