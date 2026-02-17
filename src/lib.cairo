#[starknet::contract]
mod ShadowTrade {

    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_block_timestamp};

    use starknet::storage::{
        StoragePointerReadAccess,
        StoragePointerWriteAccess,
        StoragePathEntry,
        Map
    };

    // ---------------- STORAGE ----------------

    #[storage]
    struct Storage {
        question: felt252,
        commit_deadline: u64,
        reveal_deadline: u64,
        resolved: bool,
        outcome: u8,
        admin: ContractAddress,

        commitments: Map<ContractAddress, felt252>,
        has_committed: Map<ContractAddress, bool>,
    }

    // ---------------- CONSTRUCTOR ----------------

    #[constructor]
    fn constructor(
        ref self: ContractState,
        question: felt252,
        commit_deadline: u64,
        reveal_deadline: u64
    ) {
        self.question.write(question);
        self.commit_deadline.write(commit_deadline);
        self.reveal_deadline.write(reveal_deadline);
        self.resolved.write(false);
        self.outcome.write(0);
        self.admin.write(get_caller_address());
    }

    // ---------------- MARKET INFO ----------------

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

    // ---------------- USER COMMITMENT ----------------

    #[external(v0)]
    fn get_commitment(self: @ContractState, user: ContractAddress) -> felt252 {
        self.commitments.entry(user).read()
    }

    // ---------------- COMMIT FUNCTION ----------------

    #[external(v0)]
    fn commit(ref self: ContractState, commitment_hash: felt252) {
        let caller = get_caller_address();
        let current_time = get_block_timestamp();

        let deadline = self.commit_deadline.read();
        assert(current_time <= deadline, 'Commit phase ended');

        let already_committed = self.has_committed.entry(caller).read();
        assert(!already_committed, 'Already committed');

        self.commitments.entry(caller).write(commitment_hash);
        self.has_committed.entry(caller).write(true);
    }
}