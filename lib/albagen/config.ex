defmodule Albagen.Config do
  @moduledoc """
  Module controlling the main configurations of Albagen with environment variables.
  Functions are cached in memory using Memoize
  """
  require Logger

  def show_config do
    stakers_to_create = stakers_to_create()
    sqlite_path = sqlite_path()
    albatross_nodes = albatross_nodes()
    seed_wallet_addres = seed_wallet_addres()
    new_account_min_nim = new_account_min_nim()
    new_account_max_nim = new_account_max_nim()
    timer_cap_in_secs = timer_cap_in_secs() / 1000
    allow_action_keep = allow_action_keep()

    Logger.info(
      " Albagen uses the following configuration:
        stakers_to_create   = #{stakers_to_create}
        sqlite_path         = #{sqlite_path}
        abatross_nodes      = #{albatross_nodes}
        seed_wallet_addres  = #{seed_wallet_addres}
        new_account_min_nim = #{new_account_min_nim}
        new_account_max_nim = #{new_account_max_nim}
        timer_cap_in_secs   = #{timer_cap_in_secs}
        allow_action_keep   = #{allow_action_keep}"
    )
  end

  def sqlite_path, do: Application.get_env(:albagen, :sqlite_path)

  def albatross_nodes, do: Application.get_env(:albagen, :albatross_nodes)

  def seed_wallet_addres, do: Application.get_env(:albagen, :seed_wallet_address)

  def seed_wallet_key, do: Application.get_env(:albagen, :seed_wallet_key)

  def new_account_min_nim, do: Application.get_env(:albagen, :new_account_min_nim)

  def new_account_max_nim, do: Application.get_env(:albagen, :new_account_max_nim)

  def stakers_to_create, do: Application.get_env(:albagen, :stakers_to_create)

  def timer_cap_in_secs, do: Application.get_env(:albagen, :timer_cap_in_secs)

  def allow_action_keep, do: Application.get_env(:albagen, :allow_action_keep)
end
