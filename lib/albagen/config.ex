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

    Logger.info(
      " Albagen uses the following configuration:\nstakers_to_create   = #{stakers_to_create}\nsqlite_path         = #{sqlite_path}\nabatross_nodes      = #{albatross_nodes}\nseed_wallet_addres  = #{seed_wallet_addres}\nnew_account_min_nim = #{new_account_min_nim}\nnew_account_max_nim = #{new_account_max_nim}\ntimer_cap_in_secs   = #{timer_cap_in_secs}"
    )
  end

  def sqlite_path do
    System.get_env("SQLITE_PATH", "~/albagen.sqlite")
  end

  def albatross_nodes do
    System.get_env(
      "ALBATROSS_NODES",
      "http://seed1.nimiq.local:8648,http://seed2.nimiq.local:8648,http://seed3.nimiq.local:8648,http://seed4.nimiq.local:8648"
    )
    |> String.split(",", trim: true)
  end

  def seed_wallet_addres do
    System.get_env("SEED_WALLET_ADDRESS", "NQ87 HKRC JYGR PJN5 KQYQ 5TM1 26XX 7TNG YT27")
  end

  def seed_wallet_key do
    System.get_env(
      "SEED_WALLET_PRIVATE_KEY",
      "3336f25f5b4272a280c8eb8c1288b39bd064dfb32ebc799459f707a0e88c4e5f"
    )
  end

  def new_account_min_nim do
    min_nim = System.get_env("NEW_ACCOUNT_MIN_NIM", "1") |> String.to_integer()
    max(min_nim, 1)
  end

  def new_account_max_nim do
    System.get_env("NEW_ACCOUNT_MAX_NIM", "1000") |> String.to_integer()
  end

  def stakers_to_create do
    System.get_env("STAKERS_TO_CREATE", "100") |> String.to_integer()
  end

  def timer_cap_in_secs do
    System.get_env("TIMER_CAP_IN_SECS", "600")
    |> String.to_integer()
    |> :timer.seconds()
  end
end
