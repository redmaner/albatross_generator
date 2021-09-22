defmodule Albagen.Model.Account do
  @db :albagen_sqlite

  @type t :: %__MODULE__{
          address: String.t(),
          public_key: String.t(),
          private_key: String.t(),
          node: String.t(),
          seed_number: integer(),
          is_seeded: integer()
        }

  defstruct ~w[address public_key private_key node seed_number is_seeded]a

  def parse_from_json(
        %{"address" => address, "privateKey" => private_key, "publicKey" => public_key},
        node,
        seed_number
      ) do
    {:ok,
     %__MODULE__{
       address: address,
       public_key: public_key,
       private_key: private_key,
       node: node,
       seed_number: seed_number,
       is_seeded: 0
     }}
  end

  def create_table do
    Sqlitex.Server.query(
      @db,
      "CREATE TABLE IF NOT EXISTS stakers(address TEXT PRIMARY KEY NOT NULL, public_key TEXT NOT NULL, private_key TEXT NOT NULL, node TEXT NOT NULL, seed_number INTEGER NOT NULL, is_seeded INTEGER NOT NULL);"
    )
  end

  def insert(%__MODULE__{
        address: address,
        public_key: public_key,
        private_key: private_key,
        node: node,
        seed_number: seed_number,
        is_seeded: is_seeded
      }) do
    Sqlitex.Server.query(
      :albagen_sqlite,
      "INSERT INTO stakers (address, public_key, private_key, node, seed_number, is_seeded) VALUES (?, ?, ?, ?, ?, ?)",
      bind: [
        address,
        public_key,
        private_key,
        node,
        seed_number,
        is_seeded
      ]
    )
  end

  def set_seeded(address) do
    Sqlitex.Server.query(@db, "UPDATE stakers SET is_seeded = 1 WHERE address = ?",
      bind: [address]
    )
  end

  def count_created_stakers do
    case Sqlitex.Server.query(@db, "SELECT COUNT(*) AS count_stakers FROM stakers") do
      {:ok, [[count_stakers: count_stakers]]} -> {:ok, count_stakers}
      {:ok, _result} -> {:ok, 0}
      error -> error
    end
  end

  def get_all do
    Sqlitex.Server.query(:albagen_sqlite, "SELECT * FROM stakers ORDER BY seed_number")
    |> wrap_multi_return()
  end

  defp wrap_multi_return({:ok, rows}) do
    return =
      rows
      |> Enum.map(&parse_account_from_row/1)

    {:ok, return}
  end

  defp wrap_multi_return(error), do: error

  defp parse_account_from_row(
         address: address,
         public_key: public_key,
         private_key: private_key,
         node: node,
         seed_number: seed_number,
         is_seeded: is_seeded
       ) do
    %Albagen.Model.Account{
      address: address,
      public_key: public_key,
      private_key: private_key,
      node: node,
      seed_number: seed_number,
      is_seeded: is_seeded
    }
  end
end
