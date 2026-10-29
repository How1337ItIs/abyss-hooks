// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {LaunchDirectoryV1} from "../contracts/protocol/src/launch/lifecycle/v1/LaunchDirectoryV1.sol";
import {PreparedMarketV1,PositionIdentityV1} from "../contracts/protocol/src/launch/lifecycle/v1/LaunchTypesV1.sol";
contract DirectoryGasTest {
 LaunchDirectoryV1 d;
 bytes32 constant ID=bytes32(uint256(1));
 function setUp() public {
  d=new LaunchDirectoryV1(address(this));
  d.recordLaunch(ID,address(this),address(this),address(this));
  PreparedMarketV1 memory m;
  m.identity.canonicalId=bytes32(uint256(2));
  m.custody=address(this); m.feeSource=address(this); m.positionCount=1;
  d.recordMarket(ID,0,address(this),m);
 }
 function position() internal view returns(PositionIdentityV1[] memory p) {
  p=new PositionIdentityV1[](1);
  p[0]=PositionIdentityV1(0,bytes32(uint256(2)),address(this),address(this),123,-120,120,bytes32(uint256(42)),100);
  p[0].canonicalId=keccak256(abi.encode(block.chainid,p[0].marketId,p[0].manager,p[0].custody,p[0].tokenId,p[0].tickLower,p[0].tickUpper,p[0].salt));
 }
 function testRecordGasBudget() public {
  PositionIdentityV1[] memory p=position();
  uint256 beforeGas=gasleft(); d.recordPositions(ID,0,p); uint256 used=beforeGas-gasleft();
  require(used<175000,"directory redundant storage exceeds budget");
 }
 function testRoundTripAndDuplicateGuard() public {
  PositionIdentityV1[] memory p=position(); d.recordPositions(ID,0,p);
  require(keccak256(abi.encode(d.positions(ID,0,0,100)))==keccak256(abi.encode(p)),"identity changed");
  require(d.launchOfPosition(p[0].canonicalId)==ID,"reverse index lost");
  require(d.positionCount(ID,0)==1,"count changed");
  (bool ok,)=address(d).call(abi.encodeCall(d.recordPositions,(ID,0,p))); require(!ok,"duplicate accepted");
 }
 function testFuzzRoundTrip(uint128 liquidity, uint256 tokenId, bytes32 salt) public {
  if (liquidity == 0) liquidity=1;
  PositionIdentityV1[] memory p=position();
  p[0].liquidity=liquidity; p[0].tokenId=tokenId; p[0].salt=salt;
  p[0].canonicalId=keccak256(abi.encode(block.chainid,p[0].marketId,p[0].manager,p[0].custody,p[0].tokenId,p[0].tickLower,p[0].tickUpper,p[0].salt));
  d.recordPositions(ID,0,p);
  require(keccak256(abi.encode(d.positions(ID,0,0,100)))==keccak256(abi.encode(p)),"fuzz round trip changed");
  require(d.positions(ID,0,1,100).length==0,"offset pagination changed");
  require(d.positions(ID,0,0,0).length==0,"zero limit changed");
 }
 function testInvalidIdentityRejected() public {
  PositionIdentityV1[] memory p=position(); p[0].canonicalId=bytes32(uint256(999));
  (bool ok,)=address(d).call(abi.encodeCall(d.recordPositions,(ID,0,p))); require(!ok,"bad identity accepted");
 }
}
