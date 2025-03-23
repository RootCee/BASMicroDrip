How This Contract Meets Your Requirements

Automatic Drips on Stream Registration:
Your off‑chain system (which tracks file counts on Pinata IPFS) can call the dripForTrack function when a stream is registered. The function looks up the track by its unique record CID and sends tokens accordingly.


Changeable Drip Amount & Percentage Splits:

When registering (or updating) a track, the caller specifies:
A base drip amount (the total token amount to be distributed per stream).
A split between the track owner and an optional featured artist using percentage values.
• If there is no featured artist, the track owner receives 100% of the drip amount.
• If a featured artist is provided, the owner and featured percentages must add to 100.


Track Owner Registration:

The registerTrack function automatically sets the caller’s address as the track owner. This links each track on‑chain to its owner based on the address that registered it.
Integration with Off‑Chain Storage:
While the contract only stores minimal on‑chain data (the record CID and payout parameters), all the files and detailed play counts remain stored off‑chain (on Pinata IPFS). Your backend can use the CID to look up full metadata.


Security and Authorization:

• Only authorized addresses (or the contract owner) may trigger drip payments using the onlyAuthorized modifier.
• The deposit and withdrawal functions are protected with the onlyOwner and nonReentrant modifiers.
• The contract leverages OpenZeppelin’s well‑tested libraries (Ownable and ReentrancyGuard) to improve security.


Next Steps

Deploy & Test:

Compile and deploy this contract on your testnet (Sonieum Testnet) using your preferred framework (e.g. Hardhat). Write tests (as shown in previous examples) to ensure that:
Tracks register correctly.
Drip payments split as expected.
Only authorized addresses can trigger payments.
Integrate with Your Backend:
Update your site’s backend so that once a track reaches the required stream count, it calls dripForTrack (passing the appropriate record CID) to trigger the micro drip payout.

///////////////////////////////

Front-End Integration

Within your streaming application (for example, in your React SongProvider), update the function that triggers the drip payment once 90% of a track is played. Since the smart contract no longer accepts an amount, simply call the drip function with the artist’s address:

// Example integration snippet within your handleTrackPlays function:
async function handleTrackPlays(recordCID) {
  try {
    // 1. Update play count on your backend.
    const updateMetadata = new FormData();
    updateMetadata.append('recordCID', recordCID);
    const audioResponse = await fetch('/api/ipfs/update-metadata', {
      method: 'POST',
      body: updateMetadata,
    });
    const audioResult = await audioResponse.json();
    setRecord(prev => ({ ...prev, totalPlays: parseInt(audioResult.totalPlays) }));
    if (!audioResponse.ok) {
      throw new Error(audioResult.message || 'Failed to update track plays.');
    }

    // 2. Trigger the micro drip payment.
    // Assumes microDripContract and userAccount are available in your web3 context.
    if (microDripContract && userAccount) {
      await microDripContract.methods.drip(record.royaltyRecipient).send({ from: userAccount });
    }
  } catch (error) {
    console.error('Error in handleTrackPlays:', error.message);
  }
}
# BASMicroDrip
