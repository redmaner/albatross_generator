defmodule ModelAccountTest do
  use ExUnit.Case, async: true

  alias Albagen.Model.Account

  test "multi insert query" do
    accounts = [
      %Account{
        address: "A",
        public_key: "a_pub_key",
        private_key: "a_priv_key",
        node: "node1",
        seed_number: 1
      },
      %Account{
        address: "B",
        public_key: "b_pub_key",
        private_key: "b_priv_key",
        node: "node2",
        seed_number: 2
      },
      %Account{
        address: "C",
        public_key: "c_pub_key",
        private_key: "c_priv_key",
        node: "node3",
        seed_number: 3
      }
    ]

    assert Account.create_multi_insert_query(accounts) ==
             "INSERT INTO stakers (address, public_key, private_key, node, seed_number) VALUES (A,a_pub_key,a_priv_key,node1,1), (B,b_pub_key,b_priv_key,node2,2), (C,c_pub_key,c_priv_key,node3,3);"
  end
end
