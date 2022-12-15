// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./lzApp/NonblockingLzApp.sol";
import "./interfaces/ILayerZeroReceiver.sol";

contract SideChainDAO is Ownable, ILayerZeroReceiver {
    
    uint32 nonce = 0;
    uint16 mainChainId;
    mapping(uint16 => bytes32) _daoContracts;
    mapping(bytes32 => bool) _completedMessages;

    // Create an enum named Vote containing possible options for a vote
    enum Vote {
        YES, // YES = 0
        NO, // NO = 1
        ABSTAIN // ABSTAIN = 2
    }

    enum MessageOperation {
        NEW_PROPOSAL,
        VOTING_ENDED,
        SHARING_VOTES,
        PROPOSAL_RESULT
    }
    
    // Create a struct named votes to store counts for a proposal
    struct VoteCount {
        // inFavor - number of yes votes for this proposal
        uint256 inFavor;
        // against - number of no votes for this proposal
        uint256 against;
        // abstain - number of neutral votes for this proposal
        uint256 abstain;
    }

    // Create a struct named Proposal containing all relevant information
    struct Proposal {
        // proposalTitle - The purpose of the proposal (Here represents the action to take afterwards)
        string proposalTitle;
        // deadline - the UNIX timestamp until which this proposal is active. Proposal can be executed after the deadline has been exceeded.
        uint256 deadline;
        // votes - Count of different votes cast on-chain for the proposal
        VoteCount votes;
        // votingEnded - whether or not the voting period has ended and chains have been notified
        bool votingEnded;
        // executed - whether or not this proposal has been executed yet. Cannot be executed before the deadline has been exceeded.
        bool executed;
        // proposalPassed - whether the voting outcome was in favor of the proposal or not
        bool proposalPassed;
        // voters - a mapping of addresses to booleans indicating whether the address has already been used to cast a vote or not
        mapping(address => bool) voters;
    }

    // Create a mapping of ID to Proposal
    mapping(uint256 => Proposal) public proposals;

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {}

    // Create a modifier which only allows a function to be
    // called by someone who has voting power through tokens or delegation
    modifier votingRightHolderOnly() {
        // Check for address having voting rights
        _;
    }

    // Create a modifier which only allows a function to be
    // called if the given proposal's deadline has not been exceeded yet
    modifier activeProposalOnly(uint256 proposalIndex) {
        require(
            proposals[proposalIndex].deadline > block.timestamp,
            "DEADLINE_EXCEEDED"
        );
        _;
    }

    // Registers it's DAO contracts on other chains as the only ones that can send this instance messages
    function registerDaoContracts(uint16 chainId, bytes32 daoContractAddress) public onlyOwner {
        mainChainId = chainId;
        _daoContracts[chainId] = daoContractAddress;
    }

    // pings the destination chain, along with the current number of pings sent
    function sendMessage(
        MessageOperation operation, uint256 proposalIndex
    ) public payable whenNotPaused {
        require(address(this).balance > 0, "the balance of this contract is 0. pls send gas for message fees");

        // encode the payload with the number of pings
        bytes memory payload = createMessagePayload(operation, proposalIndex);

        // use adapterParams v1 to specify more gas for the destination
        uint16 version = 1;
        uint gasForDestinationLzReceive = 350000;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        // send LayerZero message
        _lzSend( // {value: messageFee} will be paid out of this contract!
            sideChainId, // destination chainId
            payload, // abi.encode()'ed bytes
            payable(this), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
            address(0x0), // future param, unused for this example
            adapterParams, // v1 adapterParams, specify custom destination gas qty
            msg.value
        );
    }
    
    /// @dev createMessagePayload converts the operation type and proposal state to bytes to emit to the bridge contract
    function createMessagePayload(MessageOperation operation, uint256 proposalIndex)
    internal view returns (bytes memory) {
        return abi.encode(operation,
            proposalIndex,
            proposals[proposalIndex].proposalTitle,
            proposals[proposalIndex].deadline,
            proposals[proposalIndex].votes,
            proposals[proposalIndex].votingEnded,
            proposals[proposalIndex].executed,
            proposals[proposalIndex].proposalPassed
            );
    }

    /// @dev processMessagePayload processes messages received from other chain
    function processMessagePayload(bytes memory data)
    internal {
        MessageOperation operation;
        uint256 proposalIndex;
        string memory proposalTitle;
        uint256 deadline;
        VoteCount memory votes;
        bool executed;
        bool proposalPassed;
        (operation, proposalIndex, proposalTitle, deadline, votes, executed, proposalPassed) = abi.decode(data, (MessageOperation, uint256, string, uint256, VoteCount, bool, bool));

        if (operation == MessageOperation.NEW_PROPOSAL) {
            proposals[proposalIndex].proposalTitle = proposalTitle;
            proposals[proposalIndex].deadline = deadline;
        } else if (operation == MessageOperation.VOTING_ENDED) {
            proposals[proposalIndex].votingEnded = true;
            sendMessage(MessageOperation.SHARING_VOTES, proposalIndex);
        } else if (operation == MessageOperation.PROPOSAL_RESULT) {
            proposals[proposalIndex].executed = executed;
            proposals[proposalIndex].proposalPassed = proposalPassed;
        }
    }

    function lzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint _nonce, bytes memory _payload) internal override {
        require(msg.sender == address(endpoint));
        require(keccak256(_srcAddress) == keccak256(_daoContracts[_srcChainId], "Invalid Emitter Address!");
            
        //Process the Message
        processMessagePayload(_payload);
    }

    /// @dev voteOnProposal allows a voting right holder to cast their vote on an active proposal
    /// @param proposalIndex - the index of the proposal to vote on in the proposals array
    /// @param vote - the type of vote they want to cast
    function voteOnProposal(uint256 proposalIndex, Vote vote)
        external
        votingRightHolderOnly
        activeProposalOnly(proposalIndex)
    {
        require(proposals[proposalIndex].voters[msg.sender] == false, "ALREADY_VOTED");
        
        Proposal storage proposal = proposals[proposalIndex];

        if (vote == Vote.YES) {
            proposal.votes.inFavor += 1;
        } else if (vote == Vote.NO) {
            proposal.votes.against += 1;
        } else {
            proposal.votes.abstain += 1;
        }
    }
}