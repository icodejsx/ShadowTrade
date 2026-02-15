#[starknet::contract]
mod ShadowTrade {

    use starknet::ContractAddress;
    use starknet::get_caller_address;

    use starknet::storage::{
        StoragePointerReadAccess,
        StoragePointerWriteAccess
    };

    #[storage]
    struct Storage {
        question: felt252,
        commit_deadline: u64,
        reveal_deadline: u64,
        resolved: bool,
        outcome: u8, // 0 = NO, 1 = YES
        admin: ContractAddress,
    }

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
}
