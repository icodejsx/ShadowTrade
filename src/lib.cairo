mod sbtc;

#[starknet::contract]
mod ShadowTrade {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use core::pedersen::pedersen;
    use starknet::storage::{
        StoragePointerReadAccess,
        StoragePointerWriteAccess,
        StoragePathEntry,
        Map
    };

    #[starknet::interface]
    trait IERC20<TContractState> {
        fn transfer_from(
            ref self: TContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool;
        fn transfer(
            ref self: TContractState,
            recipient: ContractAddress,
            amount: u256
        ) -> bool;
        fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Committed: Committed,
        Revealed: Revealed,
        Resolved: Resolved,
        Claimed: Claimed,
    }

    #[derive(Drop, starknet::Event)]
    struct Committed {
        #[key]
        user: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Revealed {
        #[key]
        user: ContractAddress,
        vote: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct Resolved {
        outcome: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct Claimed {
        #[key]
        user: ContractAddress,
        amount: u256,
    }

    #[storage]
    struct Storage {
        question: felt252,
        commit_deadline: u64,
        reveal_deadline: u64,
        resolved: bool,
        outcome: u8,
        admin: ContractAddress,
        token: ContractAddress,
        yes_votes: u32,
        no_votes: u32,
        yes_pool: u256,
        no_pool: u256,
        commitments: Map<ContractAddress, felt252>,
        has_committed: Map<ContractAddress, bool>,
        has_revealed: Map<ContractAddress, bool>,
        has_claimed: Map<ContractAddress, bool>,
        user_vote: Map<ContractAddress, u8>,
        user_stake: Map<ContractAddress, u256>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        question: felt252,
        commit_deadline: u64,
        reveal_deadline: u64,
        token: ContractAddress,
    ) {
        self.question.write(question);
        self.commit_deadline.write(commit_deadline);
        self.reveal_deadline.write(reveal_deadline);
        self.resolved.write(false);
        self.outcome.write(0);
        self.admin.write(get_caller_address());
        self.token.write(token);
    }

    #[external(v0)]
    fn commit(ref self: ContractState, commitment_hash: felt252, stake: u256) {
        let caller = get_caller_address();
        let current_time = get_block_timestamp();

        assert(current_time <= self.commit_deadline.read(), 'Commit phase ended');
        assert(!self.has_committed.entry(caller).read(), 'Already committed');
        assert(stake > 0_u256, 'Stake must be > 0');

        let token = IERC20Dispatcher { contract_address: self.token.read() };
        token.transfer_from(caller, get_contract_address(), stake);

        self.commitments.entry(caller).write(commitment_hash);
        self.has_committed.entry(caller).write(true);
        self.user_stake.entry(caller).write(stake);

        self.emit(Committed { user: caller });
    }

    #[external(v0)]
    fn reveal(ref self: ContractState, vote: u8, secret: felt252) {
        let caller = get_caller_address();
        let current_time = get_block_timestamp();

        assert(current_time > self.commit_deadline.read(), 'Reveal not started');
        assert(current_time <= self.reveal_deadline.read(), 'Reveal phase ended');
        assert(self.has_committed.entry(caller).read(), 'No commitment found');
        assert(!self.has_revealed.entry(caller).read(), 'Already revealed');
        assert(vote == 1_u8 || vote == 2_u8, 'Vote must be 1 or 2');

        let vote_felt: felt252 = vote.into();
        let computed_hash = pedersen(vote_felt, secret);
        let stored_hash = self.commitments.entry(caller).read();
        assert(computed_hash == stored_hash, 'Invalid reveal');

        let stake = self.user_stake.entry(caller).read();
        if vote == 1_u8 {
            self.yes_votes.write(self.yes_votes.read() + 1_u32);
            self.yes_pool.write(self.yes_pool.read() + stake);
        } else {
            self.no_votes.write(self.no_votes.read() + 1_u32);
            self.no_pool.write(self.no_pool.read() + stake);
        }

        self.user_vote.entry(caller).write(vote);
        self.has_revealed.entry(caller).write(true);

        self.emit(Revealed { user: caller, vote });
    }

    #[external(v0)]
    fn resolve(ref self: ContractState, outcome: u8) {
        assert(get_caller_address() == self.admin.read(), 'Not admin');
        assert(get_block_timestamp() > self.reveal_deadline.read(), 'Reveal not ended');
        assert(!self.resolved.read(), 'Already resolved');
        assert(outcome == 1_u8 || outcome == 2_u8, 'Outcome must be 1 or 2');

        self.outcome.write(outcome);
        self.resolved.write(true);

        self.emit(Resolved { outcome });
    }

    #[external(v0)]
    fn claim(ref self: ContractState) {
        let caller = get_caller_address();

        assert(self.resolved.read(), 'Not resolved yet');
        assert(self.has_revealed.entry(caller).read(), 'Did not reveal');
        assert(!self.has_claimed.entry(caller).read(), 'Already claimed');

        let user_vote = self.user_vote.entry(caller).read();
        let outcome = self.outcome.read();
        assert(user_vote == outcome, 'Not a winner');

        let user_stake = self.user_stake.entry(caller).read();
        let winning_pool = if outcome == 1_u8 {
            self.yes_pool.read()
        } else {
            self.no_pool.read()
        };
        let losing_pool = if outcome == 1_u8 {
            self.no_pool.read()
        } else {
            self.yes_pool.read()
        };

        let winnings = (user_stake * losing_pool) / winning_pool;
        let payout = user_stake + winnings;

        self.has_claimed.entry(caller).write(true);

        let token = IERC20Dispatcher { contract_address: self.token.read() };
        token.transfer(caller, payout);

        self.emit(Claimed { user: caller, amount: payout });
    }

    #[external(v0)]
    fn get_market_info(self: @ContractState) -> (felt252, u64, u64, bool, u8) {
        (
            self.question.read(),
            self.commit_deadline.read(),
            self.reveal_deadline.read(),
            self.resolved.read(),
            self.outcome.read()
        )
    }

    #[external(v0)]
    fn get_pool_info(self: @ContractState) -> (u32, u32, u256, u256) {
        (
            self.yes_votes.read(),
            self.no_votes.read(),
            self.yes_pool.read(),
            self.no_pool.read()
        )
    }

    #[external(v0)]
    fn get_user_info(
        self: @ContractState, user: ContractAddress
    ) -> (bool, bool, bool, u8, u256) {
        (
            self.has_committed.entry(user).read(),
            self.has_revealed.entry(user).read(),
            self.has_claimed.entry(user).read(),
            self.user_vote.entry(user).read(),
            self.user_stake.entry(user).read()
        )
    }
}