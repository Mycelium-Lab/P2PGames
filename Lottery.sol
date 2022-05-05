// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Lottery is VRFConsumerBaseV2 {
    address addressOfServer;
    VRFCoordinatorV2Interface COORDINATOR =
        VRFCoordinatorV2Interface(vrfCoordinator);
    uint64 s_subscriptionId;
    address vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;
    bytes32 keyHash =
        0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;
    uint32 callbackGasLimit = 40000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;
    uint256 public randomNumber;
    uint256 requestId;

    constructor(uint64 subscriptionId) VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;
        addressOfServer = msg.sender;
    }

    struct InformationAboutPlayer {
        address address_of_player;
        uint256 amount;
        int8 lucky_number;
    }

    struct InformationAboutOneGame {
        uint256 max_amount_of_players;
        uint256 min_bid;
        uint256 amount_of_players;
        uint256 overall_amount_of_bids;
        uint256 amount_of_winners;
        bool is_ended;
        uint last_run;
        uint256[] winners_index;
    }

    mapping(uint256 => InformationAboutOneGame) public one_game;
    mapping(uint256 => mapping(uint256 => InformationAboutPlayer))
        public one_player;
    uint256[] game_index;
    uint256 amount_of_games;

    function gameReturn(
        uint256 _index_of_game,
        uint256 _max_amount_of_players,
        uint256 _bid_amount
    ) internal {
        game_index.push(amount_of_games);
        InformationAboutOneGame storage game = one_game[_index_of_game];
        game.max_amount_of_players = _max_amount_of_players;
        game.min_bid = _bid_amount;
        game.overall_amount_of_bids += _bid_amount;
        game.last_run = block.timestamp;
        game.is_ended = false;
    }

    function playerInitialization(
        uint256 _index_of_game,
        uint256 _index_of_player,
        uint256 _bid_amount,
        int8 _lucky_number,
        address _address_of_player
    ) internal {
        InformationAboutPlayer storage player = one_player[_index_of_game][
            _index_of_player
        ];
        player.address_of_player = _address_of_player;
        player.amount = _bid_amount;
        player.lucky_number = _lucky_number;
    }

    modifier is_lucky_number_in_range(int8 _lucky_number) {
        require(
            (_lucky_number >= 0) && (_lucky_number <= 100),
            "Your number must be in range 0-100"
        );
        _;
    }

    function newGame(int8 _lucky_number, uint256 _max_amount_of_players)
        public
        payable
        is_lucky_number_in_range(_lucky_number)
    {
        require(msg.value > 0, "Your bid must be more than 0");
        gameReturn(amount_of_games, _max_amount_of_players, msg.value);
        InformationAboutOneGame storage game = one_game[amount_of_games];
        playerInitialization(
            amount_of_games,
            game.amount_of_players,
            msg.value,
            _lucky_number,
            msg.sender
        );
        game.amount_of_winners = 1;
        amount_of_games++;
        game.amount_of_players++;
    }

    function bid(uint256 _index_of_game, int8 _lucky_number)
        public
        payable
        is_lucky_number_in_range(_lucky_number)
    {
        require(
            (_lucky_number >= 0) && (_lucky_number <= 100),
            "Your number must be in range 0-100"
        );
        InformationAboutOneGame storage game = one_game[_index_of_game];
        require(
            game.amount_of_players < game.max_amount_of_players,
            "You can't join this game. All places are ocupied"
        );
        require(
            msg.value > game.min_bid,
            "To join this game, your bid greater than or equal to minimum bid"
        );
        playerInitialization(
            _index_of_game,
            game.amount_of_players,
            msg.value,
            _lucky_number,
            msg.sender
        );
        game.amount_of_players++;
        game.overall_amount_of_bids += msg.value;
        if (game.amount_of_players > 3) {
            game.amount_of_winners = (3 * game.amount_of_players) / uint256(10);
        }
    }

    function requestRandomWords() internal {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
    }

    function fulfillRandomWords(uint256, uint256[] memory random_words)
        internal
        override
    {
        randomNumber = random_words[0] % 100;
    }

    function abs(int8 x) private pure returns (int8) {
        return x >= 0 ? x : -x;
    }

    function transactToWinner(uint256 _index_of_game) public payable {
        InformationAboutOneGame storage game = one_game[_index_of_game];
        require(game.is_ended == true, "This game was not ended yet");
        for (uint256 i; i < game.amount_of_winners; i++) {
            payable(
                one_player[_index_of_game][game.winners_index[i]]
                    .address_of_player
            ).transfer(game.overall_amount_of_bids / game.amount_of_winners);
        }
    }

    function revealWiners(uint256 _index_of_game) public {
        InformationAboutOneGame storage game = one_game[_index_of_game];
        require(block.timestamp - game.last_run >= 5 minutes, "You need to wait more time");
        int8[] memory lucky_numbers = new int8[](game.amount_of_players);
        for (uint256 i; i < game.amount_of_players; i++) {
            lucky_numbers[i] = one_player[_index_of_game][i].lucky_number;
        }
        requestRandomWords();
        int8 lucky = int8(int256(randomNumber));
        uint256 winners_amount;
        for (int8 i; i < 101; i++) {
            bool is_max = false;
            for (uint256 j; j < game.amount_of_players; j++) {
                if (winners_amount == game.amount_of_winners) {
                    is_max = true;
                    break;
                }
                if (
                    (lucky_numbers[j] == lucky - i) ||
                    (lucky_numbers[j] == lucky + i)
                ) {
                    game.winners_index.push(j);
                    winners_amount++;
                }
            }
            if (is_max) {
                break;
            }
        }
        game.is_ended = true;
    }
}
