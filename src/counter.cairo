use starknet::{SyscallResultTrait, ContractAddress, syscalls};
use core::serde::Serde;

#[starknet::interface]
trait IKillSwitchTrait<T> {
    fn is_active(self: @T) -> bool;
}

#[derive(Copy, Drop, starknet::Store, Serde)]
struct IKillSwitch {
    contract_address: ContractAddress,
}

impl IKillSwitchImpl of IKillSwitchTrait<IKillSwitch> {
    fn is_active(self: @IKillSwitch) -> bool {
        let mut call_data: Array<felt252> = ArrayTrait::new();
        let contract_address: ContractAddress = *self.contract_address;
        let mut res = syscalls::call_contract_syscall(
            contract_address, selector!("is_active"), call_data.span()
        )
            .unwrap_syscall();

        Serde::<bool>::deserialize(ref res).unwrap()
    }
}


#[starknet::interface]
pub trait ICounter<TContractState> {
    fn get_counter(self: @TContractState) -> u32;
    fn increase_counter(ref self: TContractState);
}

#[starknet::contract]
mod Counter {
    use openzeppelin::access::ownable::OwnableComponent;
    use core::traits::Into;
    use core::starknet::event::EventEmitter;
    use starknet::ContractAddress;
    use super::IKillSwitchTrait;
    use super::IKillSwitch;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        counter: u32,
        kill_switch: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_counter: u32,
        kill_switch: ContractAddress,
        initial_owner: ContractAddress
    ) {
        self.counter.write(initial_counter);
        self.kill_switch.write(kill_switch);
        self.ownable.initializer(initial_owner)
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CounterIncreased: CounterIncrease,
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    struct CounterIncrease {
        #[key]
        counter: u32,
    }


    #[abi(embed_v0)]
    impl CounterImpl of super::ICounter<ContractState> {
        fn get_counter(self: @ContractState) -> u32 {
            self.counter.read()
        }

        fn increase_counter(ref self: ContractState) {
            self.ownable.assert_only_owner();
            let kill_switch_address = self.kill_switch.read();
            let is_active = IKillSwitch { contract_address: kill_switch_address }.is_active();

            assert!(is_active, "Kill Switch is active");

            let previous_counter = self.counter.read();
            let current_counter = previous_counter + 1;
            self.counter.write(current_counter);
            self.emit(CounterIncrease { counter: current_counter })
        }
    }
}
