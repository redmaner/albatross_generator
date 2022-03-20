# Albagen

Albagen, short for Albatross Generator, is a tool that can be used to simulate stakers on the Nimiq Albatross blockchain. The tool's intended purpose is to contribute in testing Nimiq 2.0 Albatross.

## About 

### What does it do?
Albagen will create a predetermined set of stakers on a configurable set of Albatross nodes (one or many nodes). Stakers will be spread over the active validators. After creation of the stakers, each account will have an assigned process that mimics staker behaviour, this includes: updating stake to a different validator, updating the stake in amount, retiring stake, reactivating a retired stake and unstaking retired funds. 

### What is the intended purpose of Albagen?
Albagen has two purposes:
1. Albagen can be used locally in docker together with the docker setup of Albatross to have a simulated set of stakers for developers to use in order to develop applications, including Proof of Stake pool implementations. 
2. Albagen can be used on the testnet by multiple users to simulate a larger quantity of stakers on the testnet, in order to test albatross’ performance and throughput and provide developers with sufficient test cases to develop their projects (apps, pools etc.). 

### How does it work?
1. Albagen on startup will create a configureable amount of new accounts, and stores the account information in Sqlite. The account information is stored for two purposes:
   * In case of a restart Albagen doesn't have to create new wallets
   * Users of Albagen can use the information for other purposes.
2. After the creation of the necessary amount of accounts, Albagen will start a dedicated process for each account. 
3. Each Account process will follow the same loop:
   1. On first instance the account is seeded by a seed wallet. This means the new account will receive an initial balance from a different account (the seed wallet) which will be used to send staking contract transactions.
   2. After the initial seed, the main transaction loop begins:
      * In case the account has a balance, but doesn't have stake balance a new staker will be created with a `new staker transaction`.
      * In case the account has a balance and has a stake balance, a random staking transaction will be selected which is either: 
        * increase stake with `stake transaction`
        * change validator with `update transcation`
        * decrease stake with `unstake transaction`
      * In case the account has a stake balance but no regular balance, a random staking transaction will be selected which is either:
        * change validator with `update transcation`
        * decrease stake with `unstake transaction`
    3. After a transaction is sent, the process goes to sleep. After a certain amount of time the process is awakened and the loop repeats as described by step 2 above.

## Running albagen

### Requirements
You require the following in order to run Albagen:
1. An Albatross node or multiple Albatross nodes that have the RPC interface enabled. Albagen can use multiple Albatross nodes, in that case it will spread the transactions and accounts over the available nodes.
2. A seed wallet that will be used to provide each new account with an initial balance.

### Notes and limitations
Currently the following is important to know when using Albagen:
* Albagen currently doesn't support username and password when accessing the RPC interface of Albatross
* Albagen can run hundreds of staker processes to stress test Albatross. However, the amount of stakers that is supported is highly dependent on hardware. Albagen uses the Erlang VM which automatically scales on the available hardware, and can therefore scale vertically out of the box. 
* The amount of transactions is limited during creation of new accounts and seeding accounts. This will improve greatly once all desired accounts are created and seeded.
* Albagen doesn't support distributed Elixir / Erlang. This can be added in the future, if required. 
* Albagen can be compiled in release mode, so that a local Erlang installation is not required.

### Configuration
Albagen can be configured with environement variables:
| Env   | Description | Default |
|:------|:------------|:------------|
| ALBATROSS_NODES | The albatross node which is used to send transactions. Mutliple nodes can be provided and should be comma separated |
| SQLITE_PATH | The path to the Sqlite file that Albagen will use to save the newly created accounts | 
| STAKERS_TO_CREATE | The amount of stakers that Albagen will create to send staking contract transactions | 1000 |
| SEED_WALLET_ADDRESS | The address of the seed wallet, the wallet that is used to provide stakers with their initial balance |
| SEED_WALLET_PRIVATE_KEY | The seed wallet private key to access the account on an Albatross node |
| NEW_ACCOUNT_MIN_NIM | The minimum amount of NIM a new staker must receive from the seed wallet.| 100 NIM |
| NEW_ACCOUNT_MAX_NIM | The maximum amount of NIM a new staker should not exceed. If the min and max NIM are a range, a random amount is picked from the given range | 1000 NIM |
| TIMER_CAP_IN_SECS | The maximum time in seconds before a staker transactions should be rescheduled | 90 seconds |
| ALLOW_ACTION_KEEP | When set to true, allows the staker to keep their current staking contract state. When set to false all stakers are forced to send a transaction each cycle. Setting this to false makes Albagen more spammy. | true |

### Docker
This repository provides a reference Dockerfile to create a Docker image and a docker-compose file that is setup to work out of the box with the 4 validator setup of Albatross. 


## License

This project is under the [Apache License 2.0](./LICENSE.md).