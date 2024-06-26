use starknet::ContractAddress;

#[starknet::interface]
trait IStreaming<TContractState>{
    fn add_new_stream(
        ref self: TContractState,
        streamer: ContractAddress,
        recipient: ContractAddress,
        start_time: u64,
        end_time: u64,
        total_amount: u128
    );

    fn claim_stream(
        ref self: TContractState,
        streamer: ContractAddress,
        recipient: ContractAddress,
        start_time: u64,
        end_time: u64
     );

     fn cancel_stream(
         ref self: TContractState,
         recipient: ContractAddress,
         start_time: u64,
         end_time: u64
     );

    fn get_stream_info(
        ref self: TContractState, //TContractState?
        streamer: ContractAddress,
        recipient: ContractAddress,
        start_time: u64,
        end_time: u64,
    ) -> (u128, u128);
}

#[starknet::component]
mod streaming {
    use konoha::contract::Governance;
    use konoha::contract::{IGovernanceDispatcher, IGovernanceDispatcherTrait};
    use konoha::traits::{IGovernanceTokenDispatcher, IGovernanceTokenDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address};

    #[storage]
    struct Storage{
        streams: LegacyMap::<(ContractAddress, ContractAddress, u64, u64), (u128, u128)> // (claimed_amount, total_amount)
    }

    #[derive(starknet::Event, Drop, Serde)]
    #[event]
    enum Event{
        StreamCreated: StreamCreated,
        StreamClaimed: StreamClaimed,
        StreamCanceled: StreamCanceled
    }

    #[derive(starknet::Event, Drop, Serde)]
    struct StreamCreated{
        streamer: ContractAddress,
        recipient: ContractAddress,
        start_time: u64,
        end_time: u64,
        total_amount: u128
    }

    #[derive(starknet::Event, Drop, Serde)]
    struct StreamClaimed{
        streamer: ContractAddress,
        claimed_amount: u128
    }

    #[derive(starknet::Event, Drop, Serde)]
    struct StreamCanceled{
        streamer: ContractAddress,
        recipient: ContractAddress,
        start_time: u64,
        end_time: u64,
        reclaimed_amount: u128
    }
    //TODO:
    #[embeddable_as(StreamingImpl)]
    impl Streaming<
        TContractState, +HasComponent<TContractState>
    > of super::IStreaming<ComponentState<TContractState>> {
        fn add_new_stream(
            ref self: ComponentState<TContractState>,
            streamer: ContractAddress,
            recipient: ContractAddress,
            start_time: u64,
            end_time: u64,
            total_amount: u128
        ){
            assert(get_caller_address()== get_contract_address(), 'not self-call');
            assert(start_time < end_time, 'starts first');
            
            let key = (get_caller_address(), recipient, start_time, end_time);
            self.streams.write(key, (0, total_amount));

            self.emit(StreamCreated{
                streamer: get_caller_address(),
                recipient: recipient,
                start_time: start_time,
                end_time: end_time,
                total_amount: total_amount
            })
        }

        fn claim_stream(
            ref self: ComponentState<TContractState>,
            streamer: ContractAddress,
            recipient: ContractAddress,
            start_time: u64,
            end_time: u64
         ){
            let current_time = get_block_timestamp();

            let key: (ContractAddress, ContractAddress, u64, u64) = (
                streamer,
                recipient,
                start_time,
                end_time,
            );

            let (claimed_amount, total_amount): (u128, u128) = self.streams.read(key);

            assert(current_time > start_time, 'stream has not started');

            let elapsed_time = if current_time > end_time {
                end_time - start_time
            } else{
                current_time - start_time
            };

            let stream_duration = (end_time - start_time);
            
            let claimable_amount = (total_amount * elapsed_time.into()) / stream_duration.into();
            let amount_to_claim = claimable_amount - claimed_amount;
            assert(amount_to_claim > 0, 'nothing to claim');
            
            self.streams.write(key, (claimable_amount + amount_to_claim, total_amount));//claimable shld be (claimable_amount + amount_to_claim)
            self.streams.read(key);

            let self_dsp = IGovernanceDispatcher { contract_address: get_contract_address() };
            IGovernanceTokenDispatcher { contract_address: self_dsp.get_governance_token_address() }
                .mint(recipient, amount_to_claim.into());

            self.emit(StreamClaimed{
                streamer: streamer,
                claimed_amount: amount_to_claim,
            })
         }
    
         fn cancel_stream(
             ref self: ComponentState<TContractState>,
             recipient: ContractAddress,
             start_time: u64,
             end_time: u64
         ){
            let key: (ContractAddress, ContractAddress, u64, u64) = (
                get_caller_address(),
                recipient,
                start_time,
                end_time,
            );

            // Read from the streams LegacyMap
            let (claimed_amount, total_amount): (u128, u128) = self.streams.read(key);

            let unclaimed_amount = total_amount - claimed_amount;
            //cancel stream

            self.streams.write(key, (0,0));

            let self_dsp = IGovernanceDispatcher { contract_address: get_contract_address() };
            IGovernanceTokenDispatcher { contract_address: self_dsp.get_governance_token_address() }
                .mint(get_caller_address(), unclaimed_amount.into());
            
            self.emit(StreamCanceled{
                streamer: get_caller_address(),
                recipient: recipient,
                start_time: start_time,
                end_time: end_time,
                reclaimed_amount: unclaimed_amount,
            })
        }
        fn get_stream_info(
            ref self: ComponentState<TContractState>,
            streamer: ContractAddress,
            recipient: ContractAddress,
            start_time: u64,
            end_time: u64,
        ) -> (u128, u128) {
            let key: (ContractAddress, ContractAddress, u64, u64) = (
                streamer,
                recipient,
                start_time,
                end_time,
            );
            self.streams.read(key)
        }
        
    }
} 
