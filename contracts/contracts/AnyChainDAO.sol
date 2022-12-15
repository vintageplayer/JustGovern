// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./lzApp/NonblockingLzApp.sol";

contract AnyChainDAO is Ownable, NonblockingLzApp {
    
    uint32 nonce = 0;
    uint16 sideChainId;
    uint32 siblingCount;

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
        // siblingVoteReceivedCount - number of chains from which final vote counts have been added
        uint32 siblingVoteReceivedCount;
        // executed - whether or not this proposal has been executed yet. Cannot be executed before the deadline has been exceeded.
        bool executed;
        // proposalPassed - whether the voting outcome was in favor of the proposal or not
        bool proposalPassed;
        // voters - a mapping of addresses to booleans indicating whether the address has already been used to cast a vote or not
        mapping(address => bool) voters;
    }

    // Create a mapping of ID to Proposal
    mapping(uint256 => Proposal) public proposals;

    // Number of proposals that have been created
    uint256 public numProposals;

    // Create a payable constructor to store treasuryfunds and use it for executing proposals
    // The payable allows this constructor to accept an ETH deposit when it is being deployed
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

    // Create a modifier which only allows a function to be
    // called if the given proposals' deadline HAS been exceeded
    // and the voting reconcialitation is yet to start
    modifier readyForVotingResult(uint256 proposalIndex) {
        require(
            proposals[proposalIndex].deadline <= block.timestamp,
            "DEADLINE_NOT_EXCEEDED"
        );
        require(
            proposals[proposalIndex].votingEnded == false,
            "PROPOSAL_VOTE_COUNT_ALREADY_STARTED"
        );
        _;
    }

    // Create a modifier which only allows a function to be
    // called if the given proposals' voting results are available
    // and if the proposal has not yet been executed
    modifier readyToExecuteOnly(uint256 proposalIndex) {
        require(
            proposals[proposalIndex].votingEnded = true,
            "VOTING_AGGREGATION_IS_YET_START"
        );
        require(
            proposals[proposalIndex].siblingVoteReceivedCount == siblingCount,
            "YET_TO_RECEIVE_RESULTS_FROM_ALL_CHAINS"
        );
        require(
            proposals[proposalIndex].executed == false,
            "PROPOSAL_ALREADY_EXECUTED"
        );
        _;
    }

    // Registers it's DAO contracts on other chains as the only ones that can send this instance messages
    function registerDaoContract(uint16 chainId) public onlyOwner {
        sideChainId = chainId;
        siblingCount += 1;
    }

    // pings the destination chain, along with the current number of pings sent
    function sendMessage(
        MessageOperation operation, uint256 proposalIndex
    ) public payable {
        require(address(this).balance > 0, "the balance of this contract is 0. pls send gas for message fees");

        // encode the payload with the number of pings
        bytes memory payload = createMessagePayload(operation, proposalIndex);

        // use adapterParams v1 to specify more gas for the destination
        // uint16 version = 1;
        // uint gasForDestinationLzReceive = 350000;
        // bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        // send LayerZero message
        _lzSend( // {value: messageFee} will be paid out of this contract!
            sideChainId, // destination chainId
            payload, // abi.encode()'ed bytes
            payable(msg.sender), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
            address(0x0), // future param, unused for this example
            bytes(""), // v1 adapterParams, specify custom destination gas qty
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

        if (operation == MessageOperation.SHARING_VOTES) {
            proposals[proposalIndex].votes.inFavor += votes.inFavor;
            proposals[proposalIndex].votes.against += votes.against;
            proposals[proposalIndex].votes.abstain += votes.abstain;
            proposals[proposalIndex].siblingVoteReceivedCount += 1;
        }
    }

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal override {
        //Process the Message
        processMessagePayload(_payload);
    }

    /// @dev createProposal allows a AnyChainDAO voting rights holder to create a new proposal in the DAO
    /// @param proposalTitle - The proposal to execute based on voting outcome
    /// @return Returns the proposal index for the newly created proposal
    function createProposal(string calldata proposalTitle)
        external
        votingRightHolderOnly
        returns (uint256)
    {
        Proposal storage proposal = proposals[numProposals];
        proposal.proposalTitle = proposalTitle;
        // Set the proposal's voting deadline to be (current time + 10 minutes)
        proposal.deadline = block.timestamp + 10 minutes;
        sendMessage(MessageOperation.NEW_PROPOSAL, numProposals);
        numProposals++;

        return numProposals - 1;
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

    function endVoting(uint256 proposalIndex)
        external
        votingRightHolderOnly
        //modified Needed here to
    {
        proposals[proposalIndex].votingEnded = true;
        sendMessage(MessageOperation.VOTING_ENDED, proposalIndex);
    }

    /// @dev executeProposal allows any voting right holder to execute a proposal after it's deadline has been exceeded
    /// @param proposalIndex - the index of the proposal to execute in the proposals array
    function executeProposal(uint256 proposalIndex)
        external
        votingRightHolderOnly
        readyToExecuteOnly(proposalIndex)
    {
        Proposal storage proposal = proposals[proposalIndex];

        // If the proposal has more YES votes than NO votes
        // mark the outcome has success
        if (proposal.votes.inFavor > proposal.votes.against) {
            proposal.proposalPassed = true;
        }
        proposal.executed = true;
        sendMessage(MessageOperation.PROPOSAL_RESULT, proposalIndex);
    }

    /// @dev withdrawEther allows the contract owner (deployer) to withdraw the ETH from the contract
    function withdrawEther() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // The following two functions allow the contract to accept ETH deposits
    // directly from a wallet without calling a function
    receive() external payable {}

    fallback() external payable {}
}