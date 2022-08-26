module WSolStake::Staking {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::coins;
    use aptos_framework::managed_coin;

    const EPOOL_NOT_INITIALIZED: u64 = 0;
    const EUSER_DIDNT_STAKE: u64 = 1;
    const EINVALID_BALANCE: u64 = 2;
    const EINVALID_VALUE: u64 = 3;

    struct StakeInfo has key, store, drop {
        amount: u64,
    }

    struct PoolInfo has key, store {
        admin_addr: address,
        stakers_count: u64,
        resource_cap: account::SignerCapability
    }

    public entry fun initialize<CoinType>(admin: &signer, seeds: vector<u8>) {
        let admin_addr = signer::address_of(admin);
        let (pool, pool_signer_cap) = account::create_resource_account(admin, seeds);
        move_to<PoolInfo>(&pool, PoolInfo { admin_addr, stakers_count: 0, resource_cap: pool_signer_cap });
        coins::register<CoinType>(&pool);
    }

    public entry fun stake<CoinType>(staker: &signer, amount: u64, pool_addr: address) acquires PoolInfo, StakeInfo {
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);

        let staker_addr = signer::address_of(staker);
        if (!exists<StakeInfo>(staker_addr)) {
            move_to<StakeInfo>(staker, StakeInfo { amount });        
            let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
            pool_info.stakers_count = pool_info.stakers_count + 1;
        } else {
            let stake_info = borrow_global_mut<StakeInfo>(staker_addr);
            stake_info.amount = stake_info.amount + amount;
        };
        
        coin::transfer<CoinType>(staker, pool_addr, amount);
    }

    public entry fun unstake<CoinType>(unstaker: &signer, pool_addr: address) acquires PoolInfo, StakeInfo {
        let staker_addr = signer::address_of(unstaker);
        assert!(exists<StakeInfo>(staker_addr), EUSER_DIDNT_STAKE);
        
        let stake_info = borrow_global_mut<StakeInfo>(staker_addr);
        
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        pool_info.stakers_count = pool_info.stakers_count - 1;

        let pool_account_from_cap = account::create_signer_with_capability(&pool_info.resource_cap);
        coin::transfer<CoinType>(&pool_account_from_cap, staker_addr, stake_info.amount);

        stake_info.amount = 0;
    }

    #[test_only]
    struct WSolCoin {}

    #[test_only]
    public fun get_resource_account(source: address, seed: vector<u8>): address {
        use std::hash;
        use std::bcs;
        use std::vector;
        let bytes = bcs::to_bytes(&source);
        vector::append(&mut bytes, seed);
        let addr = account::create_address_for_test(hash::sha3_256(bytes));
        addr
    }

    #[test(alice = @0x1, stakeModule = @WSolStake)]
    public entry fun can_initialize(alice: signer, stakeModule: signer) acquires PoolInfo, StakeInfo {
        let alice_addr = signer::address_of(&alice);
        // initialize token
        managed_coin::initialize<WSolCoin>(&stakeModule, b"Wrapped Sol", b"Wsol", 9, false);

        // check alice's token balance
        coin::register_for_test<WSolCoin>(&alice);
        managed_coin::mint<WSolCoin>(&stakeModule, alice_addr, 10000);
        assert!(coin::balance<WSolCoin>(alice_addr) == 10000, EINVALID_BALANCE);

        // initialize pool
        initialize<WSolCoin>(&stakeModule, b"wsol-pool");

        // check pool balance
        let pool_addr = get_resource_account(@WSolStake, b"wsol-pool");
        assert!(coin::balance<WSolCoin>(pool_addr) == 0, EINVALID_BALANCE);

        // alice stake 1000 to pool
        stake<WSolCoin>(&alice, 1000, pool_addr);

        // check stake result
        assert!(coin::balance<WSolCoin>(alice_addr) == 9000, EINVALID_BALANCE);
        assert!(coin::balance<WSolCoin>(pool_addr) == 1000, EINVALID_BALANCE);

        let pool_info = borrow_global<PoolInfo>(pool_addr);
        assert!(pool_info.stakers_count == 1, EINVALID_VALUE);

        // alice unstake all from pool
        unstake<WSolCoin>(&alice, pool_addr);
        assert!(coin::balance<WSolCoin>(alice_addr) == 10000, EINVALID_BALANCE);
        assert!(coin::balance<WSolCoin>(pool_addr) == 0, EINVALID_BALANCE);

        let pool_info = borrow_global<PoolInfo>(pool_addr);
        assert!(pool_info.stakers_count == 0, EINVALID_VALUE);

    }

}