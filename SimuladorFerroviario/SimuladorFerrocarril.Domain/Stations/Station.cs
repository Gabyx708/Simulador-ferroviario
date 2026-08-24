using SimuladorFerrocarril.Domain.Core;

namespace SimuladorFerrocarril.Domain.Stations
{
    public class Station : Entity<Guid>
    {
        public string Name { get; private set; }

        public string Code { get; private set; }

        public Station(
            Guid id,
            string name,
            string code)
            : base(id)
        {
            if (string.IsNullOrWhiteSpace(name))
                throw new DomainException(
                    "Station name cannot be empty.");

            if (string.IsNullOrWhiteSpace(code))
                throw new DomainException(
                    "Station code cannot be empty.");

            Name = name;
            Code = code;
        }

        protected Station()
        {
            Name = null!;
            Code = null!;
        }
    }
}
