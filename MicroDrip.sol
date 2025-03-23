// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MicroDrip
 * @dev Distributes ERC20 tokens as micro drips for song streams. Tracks are registered on-chain
 * using their record CID (from IPFS via Pinata) along with associated payout parameters.
 *
 * Key Features:
 * - A track is registered with its owner (msg.sender), an optional featured artist,
 *   a base drip amount (per stream), and percentages to split the payout.
 * - Only authorized addresses (or the contract owner) can trigger drip payments.
 * - When a stream is registered (off-chain), the dripForTrack function is called,
 *   which sends tokens to the track owner and, if applicable, the featured artist.
 * - The contract includes functions for depositing tokens and updating track data.
 */
contract MicroDrip is Ownable, ReentrancyGuard {
    IERC20 public token;

    // Authorized addresses can trigger drip payments.
    mapping(address => bool) public authorized;

    // Structure to store track details.
    struct Track {
        string recordCID;           // The unique identifier (IPFS CID) for the track.
        address owner;              // The address that registered the track.
        address featuredArtist;     // Optional featured artist address.
        uint256 dripAmount;         // Base amount of tokens to drip per stream.
        uint8 ownerPercentage;      // Percentage (0-100) of the drip amount to the track owner.
        uint8 featuredPercentage;   // Percentage (0-100) for the featured artist (if any).
        bool exists;                // Flag to check if track is registered.
    }
    
    // Mapping from a track's record CID to its details.
    mapping(string => Track) public tracks;

    // Events for transparency.
    event TrackRegistered(
        string indexed recordCID,
        address indexed owner,
        address indexed featuredArtist,
        uint256 dripAmount,
        uint8 ownerPercentage,
        uint8 featuredPercentage
    );
    event TrackUpdated(string indexed recordCID);
    event Dripped(
        string indexed recordCID,
        address indexed trackOwner,
        uint256 ownerAmount,
        address featuredArtist,
        uint256 featuredAmount
    );
    event AuthorizedAddressSet(address indexed addr, bool status);
    event TokenDeposited(address indexed sender, uint256 amount);
    event TokenWithdrawn(address indexed owner, uint256 amount);

    /**
     * @dev Initializes the contract with the ERC20 token address.
     * The deployer (msg.sender) is set as the owner and is automatically authorized.
     */
    constructor(address tokenAddress) Ownable(msg.sender) {
        require(tokenAddress != address(0), "Token address cannot be zero");
        token = IERC20(tokenAddress);
        authorized[msg.sender] = true;
    }

    /// @notice Modifier to restrict function calls to authorized addresses.
    modifier onlyAuthorized() {
        require(authorized[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    /**
     * @notice Sets or updates an address’s authorization status.
     * @param _addr The address to update.
     * @param _status True to authorize, false to deauthorize.
     */
    function setAuthorized(address _addr, bool _status) external onlyOwner {
        require(_addr != address(0), "Invalid address");
        authorized[_addr] = _status;
        emit AuthorizedAddressSet(_addr, _status);
    }

    /**
     * @notice Registers a new track.
     * @param recordCID The unique identifier (IPFS CID) for the track.
     * @param featuredArtist Optional featured artist address (set to address(0) if none).
     * @param dripAmount The base token amount to drip per stream.
     * @param ownerPercentage Percentage of the drip amount for the track owner.
     * @param featuredPercentage Percentage of the drip amount for the featured artist.
     *
     * Requirements:
     * - The track must not already be registered.
     * - If a featured artist is set, ownerPercentage + featuredPercentage must equal 100.
     * - If no featured artist is set, ownerPercentage must be 100.
     */
    function registerTrack(
        string calldata recordCID,
        address featuredArtist,
        uint256 dripAmount,
        uint8 ownerPercentage,
        uint8 featuredPercentage
    ) external {
        require(!tracks[recordCID].exists, "Track already registered");

        if (featuredArtist != address(0)) {
            require(ownerPercentage + featuredPercentage == 100, "Percentages must add up to 100");
        } else {
            require(ownerPercentage == 100, "Owner percentage must be 100 if no featured artist");
        }

        tracks[recordCID] = Track({
            recordCID: recordCID,
            owner: msg.sender,
            featuredArtist: featuredArtist,
            dripAmount: dripAmount,
            ownerPercentage: ownerPercentage,
            featuredPercentage: featuredPercentage,
            exists: true
        });

        emit TrackRegistered(recordCID, msg.sender, featuredArtist, dripAmount, ownerPercentage, featuredPercentage);
    }

    /**
     * @notice Updates an existing track’s payout parameters.
     * @param recordCID The unique identifier (IPFS CID) for the track.
     * @param featuredArtist Optional featured artist address (set to address(0) if none).
     * @param dripAmount The new base token amount to drip per stream.
     * @param ownerPercentage New percentage for the track owner.
     * @param featuredPercentage New percentage for the featured artist.
     *
     * Requirements:
     * - The track must already be registered.
     * - Only the track owner or the contract owner can update the track.
     * - Percentage rules apply as in registration.
     */
    function updateTrack(
        string calldata recordCID,
        address featuredArtist,
        uint256 dripAmount,
        uint8 ownerPercentage,
        uint8 featuredPercentage
    ) external {
        require(tracks[recordCID].exists, "Track not registered");
        require(msg.sender == tracks[recordCID].owner || msg.sender == owner(), "Not authorized to update track");

        if (featuredArtist != address(0)) {
            require(ownerPercentage + featuredPercentage == 100, "Percentages must add up to 100");
        } else {
            require(ownerPercentage == 100, "Owner percentage must be 100 if no featured artist");
        }

        // Update track details.
        tracks[recordCID].featuredArtist = featuredArtist;
        tracks[recordCID].dripAmount = dripAmount;
        tracks[recordCID].ownerPercentage = ownerPercentage;
        tracks[recordCID].featuredPercentage = featuredPercentage;

        emit TrackUpdated(recordCID);
    }

    /**
     * @notice Triggers a drip payment for a registered track.
     * This function should be called automatically (via your backend)
     * when a song count is registered on the site.
     * @param recordCID The unique identifier (IPFS CID) for the track.
     *
     * The function calculates:
     * - The owner's payout as (dripAmount * ownerPercentage / 100)
     * - If a featured artist exists, their payout as (dripAmount * featuredPercentage / 100)
     *
     * Requirements:
     * - The track must be registered.
     * - The contract must hold at least dripAmount tokens.
     */
    function dripForTrack(string calldata recordCID) external onlyAuthorized nonReentrant {
        require(tracks[recordCID].exists, "Track not registered");

        Track memory track = tracks[recordCID];
        uint256 totalDrip = track.dripAmount;

        // Calculate payouts.
        uint256 ownerPayout = (totalDrip * track.ownerPercentage) / 100;
        uint256 featuredPayout = 0;
        if (track.featuredArtist != address(0)) {
            featuredPayout = (totalDrip * track.featuredPercentage) / 100;
        }

        require(token.balanceOf(address(this)) >= totalDrip, "Insufficient contract balance");

        // Transfer tokens to track owner.
        require(token.transfer(track.owner, ownerPayout), "Token transfer to track owner failed");

        // Transfer tokens to featured artist if set.
        if (track.featuredArtist != address(0)) {
            require(token.transfer(track.featuredArtist, featuredPayout), "Token transfer to featured artist failed");
        }

        emit Dripped(recordCID, track.owner, ownerPayout, track.featuredArtist, featuredPayout);
    }

    /**
     * @notice Deposits tokens into the contract for drip payments.
     * The owner must approve the token transfer beforehand.
     * @param amount The amount of tokens to deposit.
     */
    function depositTokens(uint256 amount) external onlyOwner nonReentrant {
        require(token.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        emit TokenDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraws tokens from the contract (owner only).
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(token.balanceOf(address(this)) >= amount, "Insufficient contract balance");
        require(token.transfer(owner(), amount), "Token transfer failed");
        emit TokenWithdrawn(owner(), amount);
    }
}
