defmodule Albagen.Model.Account do
  @type t :: %__MODULE__{
          address: String.t(),
          public_key: String.t(),
          private_key: String.t(),
          node: String.t(),
          validator: String.t()
        }

  defstruct ~w[address public_key private_key node validator]a

  def parse_from_json(
        %{"address" => address, "privateKey" => private_key, "publicKey" => public_key},
        node,
        validator
      ) do
    {:ok,
     %__MODULE__{
       address: address,
       public_key: public_key,
       private_key: private_key,
       node: node,
       validator: validator
     }}
  end
end
