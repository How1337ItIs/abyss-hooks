// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LaunchDirectoryV1} from "../contracts/protocol/src/launch/lifecycle/v1/LaunchDirectoryV1.sol";
import {PreparedMarketV1, PositionIdentityV1} from "../contracts/protocol/src/launch/lifecycle/v1/LaunchTypesV1.sol";

interface DirectoryVm {
    function chainId(uint256) external;
    function prank(address) external;
}

contract DirectoryBehaviorTest {
    DirectoryVm constant vm = DirectoryVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 constant ID = bytes32(uint256(1));
    bytes32 constant MARKET = bytes32(uint256(2));
    LaunchDirectoryV1 d;

    function setUp() public {
        d = new LaunchDirectoryV1(address(this));
        d.recordLaunch(ID, address(this), address(this), address(this));
        PreparedMarketV1 memory m;
        m.identity.canonicalId = MARKET;
        // Prepared manager intentionally zero: position manager is independent.
        m.custody = address(this);
        m.feeSource = address(this);
        m.positionCount = 2;
        d.recordMarket(ID, 0, address(this), m);
    }

    function canonical(PositionIdentityV1 memory p) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, p.marketId, p.manager, p.custody,
            p.tokenId, p.tickLower, p.tickUpper, p.salt));
    }

    function batch() internal view returns (PositionIdentityV1[] memory p) {
        p = new PositionIdentityV1[](2);
        for (uint256 i; i < 2; ++i) {
            p[i] = PositionIdentityV1(bytes32(0), MARKET, address(this), address(this),
                123 + i, -120, 120, bytes32(i + 42), uint128(100 + i));
            p[i].canonicalId = canonical(p[i]);
        }
    }

    function equal(PositionIdentityV1 memory a, PositionIdentityV1 memory b) internal pure {
        require(keccak256(abi.encode(a)) == keccak256(abi.encode(b)), "position mismatch");
    }

    function rejected(PositionIdentityV1[] memory p, uint32 index, bytes4 error_) internal {
        (bool ok, bytes memory reason) = address(d).call(abi.encodeCall(d.recordPositions, (ID, index, p)));
        require(!ok && keccak256(reason) == keccak256(abi.encodeWithSelector(error_)), "wrong exact error");
        require(d.positionCount(ID, 0) == 0, "partial positions retained");
        for (uint256 i; i < p.length; ++i) {
            require(d.launchOfPosition(p[i].canonicalId) == bytes32(0), "partial reverse index retained");
        }
    }

    function testDuplicateWithinBatchRollsBackCompletely() public {
        PositionIdentityV1[] memory p = batch();
        p[1] = p[0];
        rejected(p, 0, LaunchDirectoryV1.DuplicateIdentity.selector);
        require(d.positions(ID, 0, 0, 100).length == 0, "partial page retained");
        require(d.marketCount(ID) == 1 && d.launchCount() == 1, "parent records changed");
        require(d.launchOfMarket(MARKET) == ID && d.launchOfToken(address(this)) == ID, "parent indexes changed");
        // Both original identities remain usable after the failed batch.
        p = batch();
        d.recordPositions(ID, 0, p);
        require(d.positionCount(ID, 0) == 2, "rollback prevented retry");
        equal(d.positions(ID, 0, 0, 1)[0], p[0]);
        equal(d.positions(ID, 0, 1, 1)[0], p[1]);
    }

    function testMultiPositionRoundTripAndPartialPagination() public {
        PositionIdentityV1[] memory p = batch();
        d.recordPositions(ID, 0, p);
        PositionIdentityV1[] memory all = d.positions(ID, 0, 0, 100);
        require(all.length == 2 && d.positionCount(ID, 0) == 2, "count mismatch");
        for (uint256 i; i < 2; ++i) {
            equal(all[i], p[i]);
            equal(d.positions(ID, 0, i, 1)[0], p[i]);
            require(d.launchOfPosition(p[i].canonicalId) == ID, "reverse index missing");
        }
        require(d.positions(ID, 0, 1, 100).length == 1, "tail length");
        require(d.positions(ID, 0, 2, 1).length == 0, "end offset");
        require(d.positions(ID, 0, type(uint256).max, 1).length == 0, "large offset");
        require(d.positions(ID, 0, 0, 0).length == 0, "zero limit");
    }

    function testChainIdChangePreservesRecordedIdentity() public {
        PositionIdentityV1[] memory p = batch();
        d.recordPositions(ID, 0, p);
        vm.chainId(block.chainid == 1 ? 2 : 1);
        PositionIdentityV1[] memory all = d.positions(ID, 0, 0, 100);
        for (uint256 i; i < 2; ++i) {
            equal(all[i], p[i]);
            require(canonical(all[i]) != p[i].canonicalId, "chain did not change hash");
            require(d.launchOfPosition(p[i].canonicalId) == ID, "reverse index changed");
        }
    }

    function testUnauthorizedCaller() public {
        PositionIdentityV1[] memory p = batch();
        vm.prank(address(0xBEEF));
        (bool ok, bytes memory reason) = address(d).call(abi.encodeCall(d.recordPositions, (ID, 0, p)));
        require(!ok && keccak256(reason) == keccak256(abi.encodeWithSelector(LaunchDirectoryV1.Unauthorized.selector)), "wrong authorization error");
        require(d.positionCount(ID, 0) == 0 && d.launchOfPosition(p[0].canonicalId) == bytes32(0), "unauthorized write");
    }

    function testInvalidMarketRejected() public {
        PositionIdentityV1[] memory p = batch(); p[1].marketId = bytes32(uint256(99)); p[1].canonicalId = canonical(p[1]);
        rejected(p, 0, LaunchDirectoryV1.InvalidRecord.selector);
    }
    function testUnknownMarketRejected() public { rejected(batch(), 1, LaunchDirectoryV1.InvalidRecord.selector); }
    function testInvalidCustodyRejected() public {
        PositionIdentityV1[] memory p = batch(); p[1].custody = address(d); p[1].canonicalId = canonical(p[1]);
        rejected(p, 0, LaunchDirectoryV1.InvalidRecord.selector);
    }
    function testInvalidManagerRejected() public {
        PositionIdentityV1[] memory p = batch(); p[1].manager = address(0xBEEF); p[1].canonicalId = canonical(p[1]);
        rejected(p, 0, LaunchDirectoryV1.InvalidRecord.selector);
    }
    function testInvalidCountRejected() public {
        PositionIdentityV1[] memory p = new PositionIdentityV1[](1); p[0] = batch()[0];
        rejected(p, 0, LaunchDirectoryV1.InvalidRecord.selector);
    }
    function testEqualTicksRejected() public {
        PositionIdentityV1[] memory p = batch(); p[1].tickLower = p[1].tickUpper; p[1].canonicalId = canonical(p[1]);
        rejected(p, 0, LaunchDirectoryV1.InvalidRecord.selector);
    }
    function testReversedTicksRejected() public {
        PositionIdentityV1[] memory p = batch(); p[1].tickLower = 121; p[1].canonicalId = canonical(p[1]);
        rejected(p, 0, LaunchDirectoryV1.InvalidRecord.selector);
    }
    function testZeroLiquidityRejected() public {
        PositionIdentityV1[] memory p = batch(); p[1].liquidity = 0;
        rejected(p, 0, LaunchDirectoryV1.InvalidRecord.selector);
    }
    function testFuzzPackedSignedTicksAndIndependentManager(int24 lower, int24 upper, uint128 liquidity, bool otherManager) public {
        if (lower == upper) { lower = type(int24).min; upper = type(int24).max; }
        if (lower > upper) (lower, upper) = (upper, lower);
        PositionIdentityV1[] memory p = batch();
        p[0].tickLower = lower; p[0].tickUpper = upper;
        p[0].liquidity = liquidity == 0 ? 1 : liquidity;
        p[0].manager = otherManager ? address(d) : address(this);
        p[0].canonicalId = canonical(p[0]);
        d.recordPositions(ID, 0, p);
        equal(d.positions(ID, 0, 0, 1)[0], p[0]);
        equal(d.positions(ID, 0, 1, 1)[0], p[1]);
        (, PreparedMarketV1 memory m) = d.market(ID, 0);
        require(m.identity.manager == address(0) && p[0].manager != address(0), "manager fixture invalid");
    }
}
