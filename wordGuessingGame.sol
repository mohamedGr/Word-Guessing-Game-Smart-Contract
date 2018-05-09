pragma solidity ^0.4.21;

contract WordGuessingGame{
    /* 
        @author: Mohamed Grissa
        04/15/2018
        This contract was developed and tested using Remix IDE
		
        Please follow this sequence when invoking the different functions:
            1- register(): Register both players
            2- commitWord(): Commit the word of each players by submitting a hash of it following the commit-reveal pattern
            3- submitChallenge(): Each player submits the challenge corresponding to their word 
            4- play(): Each player makes a guess and submitts the obtained Words 
            5- reveal(): At the end of the game each player reveals their word
            At this point thWinner will be one of the players or will remain address(0)
            
        For simplicity, words are assumed to be lowercase
    */
    
    
    struct Player{  
        address _address;
        uint bet;                   // the bet deposited at the beginning of the game
        string challenge;           // original word with 2 characters hidden
        string guess;
        uint score;                 // score after guessing two character
        bool ready;                 // the player has submitted a word and a challenge   
        uint16 challengeIndex1;     // indices of the first and second characters to be guessed by the opponent
	uint16 challengeIndex2; 
        bool played;                // whther the player has made a guess or not
        uint gains;                 // total gain at the end of the game
    }
    
    Player[2] private players;      // Players
    Player public theWinner;        // The winner

    mapping(address => bytes32) public wordCommits;  // holds a map of player's address to their committed hash
     
    bool public gameFinished;       // whether both players have submitted their guesses
    bool public gameReady;          // whether both players have submitted their bets, words, and challeneges
    bool public player1Committed;   // whether a player has committed the hash of his/her word
    bool public player2Committed;
    bool public player1Revealed;    // whether a player has revealed the word
    bool public player2Revealed;
    bool public player1Cheater;     // whether a player has cheated after comparing the committed hash to the revealed word
    bool public player2Cheater;
	
    uint public commitPhaseEndTime; // period during which players can commit their words
    uint minimumBet;                // a minimum bet is required to be able to participate
    uint16 constant wordSize = 5; 
    uint8 count = 0;
    
    event GameStartsEvent(address player1, address player2); 
    event EndOfGameEvent(address winner, uint gains);
    event logString(string);
    event Tie(string);
    
    /*
        onlyRegisteredPlayers: modifier to ensure that only a registered player can invoke the function
    */
    modifier onlyRegisteredPlayers(){
        require(msg.sender == players[0]._address || msg.sender == players[1]._address);
        _;
    } 
    
    /*
        commitmentDone: modifier to ensure that both players have committed their words
    */
    modifier commitmentDone(){
        require(player1Committed == true && player2Committed == true);
        _;
    }
    
    /*
        WordGuessingGame(): - Constructor to initliaze the contract. It sets the minimum amount for bets and the duration of the commit phase in seconds.
    */ 
    function WordGuessingGame(uint _minimumBet, uint _commitPhaseLengthInSeconds) public{ 
        minimumBet = _minimumBet;
        commitPhaseEndTime = now + _commitPhaseLengthInSeconds * 1 seconds;
    }

    /*
        register(): - Both pPlayers must register before starting the Game
                    - The players must be different
    */
    function register() public payable{
        require(count < 2);
        require(players[count]._address == address(0));
        require(msg.value >= minimumBet);
        if(count == 1){
            require(msg.sender != players[0]._address);
        }
        players[count] = Player(msg.sender,msg.value,"","",0,false,wordSize,wordSize,false,0);
        count++;
    }

    /*
        commitWord(): - Each player commits a word by submitting the hash of it. This serves to keep the word secret until the end of the game and makes sure that 
        nobody is cheating.
                      - This follows the commit-reveal pattern
                      - Input format "0xhash", e.g. if the word is "board", then _commitWord = "0x137fc2c1ad84fb9792558e24bd3ce1bec31905160863bc9b3f79662487432e48"
                      - https://emn178.github.io/online-tools/keccak_256.html could be used to calculate Keccak-256(word)
    */
    function commitWord(bytes32 _commitWord) public onlyRegisteredPlayers{
        
        // Only allow commits during committing period
        require(now <= commitPhaseEndTime); 
        require(wordCommits[msg.sender] == 0);
        wordCommits[msg.sender] = _commitWord;
        if(msg.sender == players[0]._address){
            player1Committed = true;
        }else{
            player2Committed = true;
        }
    }
    
    /*
        submitChallenge(): - Each player needs to submit their challenge by hiding only two letters from the original word and sharing the position of the missing letters
                           - Only registered players that have committed their words can invoke this function
                           - Examples: {"words": challenge = "w_r_s" , i = 1 , j = 3 ; "board": challenge = "__ard" , i = 0 , j = 1}
    */
    function submitChallenge(string challenge, uint16 i, uint16 j) public onlyRegisteredPlayers commitmentDone{
        require(!gameReady && (msg.sender == players[0]._address || msg.sender == players[1]._address));
        require(bytes(challenge).length == wordSize);
        if(msg.sender == players[0]._address) {
            require(players[0].ready == false);
            players[0].challenge = challenge;
            players[0].challengeIndex1 = i;
            players[0].challengeIndex2 = j;
            players[0].ready = true;
        }else{
            require(players[1].ready == false);
            players[1].challenge = challenge;
            players[1].challengeIndex1 = i; 
            players[1].challengeIndex2 = j;
            players[1].ready = true;
        }
        
        if(players[0].ready && players[1].ready){
            
            // If both players are ready then they can starting playing
            gameReady = true; 
            emit GameStartsEvent(players[0]._address,players[1]._address);
        } 
    }
    
    /*
        play(): - This is where both players make their guesses
                - Only registered players that have committed their words can invoke this function
    */
    function play(string guess) public onlyRegisteredPlayers commitmentDone{ 
    	require(gameReady && !gameFinished);
    	if(msg.sender == players[0]._address) {
    	    
    	    // A player can make only one guess
    		require(players[0].played == false);
    		players[0].guess = guess;
    		players[0].played = true;

    	} else { 
    		require(players[1].played == false);
    		players[1].guess = guess;
    		players[1].played = true;
    	}
    }
    
    /*
        reveal(): - Each player is required to reveal the word that he/she committed at the beginning of the gameFinished.
                  - Only registered players that have committed their words can invoke this function
    */
    function reveal(string _word) public onlyRegisteredPlayers commitmentDone{
        // Both players must have made their guesses before reaching this step
        require(gameReady && !gameFinished && players[0].played && players[1].played);
        
        // Players must reveal their words only once
        if(msg.sender == players[0]._address && !player1Revealed){
            player1Revealed = true;
            
            // We check the committed hash against the hash of the revealed word and declare the player as cheater if there is no match
            if (wordCommits[players[0]._address] != keccak256(_word)) {
                emit logString('Word hash does not match word commit!');
                player1Cheater = true;
                return;
                
            }else{
                
                // Only If the revealed word is correct then we can calculate the opponent's score, otherwise the score cannot be calculated
                players[1].score = compareWords(players[1].guess,_word,players[0].challengeIndex1,players[0].challengeIndex2);
            }

        }else if(msg.sender == players[1]._address && !player2Revealed){
            player2Revealed = true;
            
            if (wordCommits[players[1]._address] != keccak256(_word)) {
                emit logString('Word hash does not match word commit!');
                player2Cheater = true;
                return; 
                
            }else{
                players[0].score = compareWords(players[0].guess,_word,players[1].challengeIndex1,players[1].challengeIndex2);
            }
        }
        
        if(player1Revealed && player2Revealed){
			endOfGame();
        }
    }
    
    /*
        compareWords(): - Compares two letters of two words and returns a score that reflects the number of correct letters
    */
    function compareWords(string _a, string _b, uint16 i, uint16 j) internal pure returns (uint score){
        bytes memory a = bytes(_a);
        bytes memory b = bytes(_b);
        uint diff = 0;
        require(a.length == b.length);
        
        // If the hashes of the two words are equal then we are done
        if(keccak256(_a) == keccak256(_b)){
            score = 2;
        }
        else{
            if(a[i] != b[i]){
                diff++;
            }
            if(a[j] != b[j]){
                diff++;
            }
            score = 2 - diff;
        }
        
    }
    
    /*
        endOfGame(): - This handles the distribution of prizes at the end of the game
    */
    function endOfGame() internal {
        gameFinished = true;
        
        if(!player1Cheater && !player2Cheater){
            
            // If there is no tie and no cheater then the winner will be the player with the highest score
            if(players[0].score > players[1].score){
                theWinner = players[0];
            } else if(players[0].score < players[1].score){
                theWinner = players[1]; 
            }
            
            // If there is a winner, the winner will get both bets
            if(theWinner._address != address(0)){
                theWinner.gains += address(this).balance;
                theWinner._address.transfer(address(this).balance);
                emit EndOfGameEvent(theWinner._address, address(this).balance);
             
            }else{
                // If there is no winner, then either one or both palyers are cheaters or there is a tie.
                emit Tie("There is a tie! Both palyers will receive their bets back!");
                players[0]._address.transfer(players[0].bet);
                players[1]._address.transfer(players[1].bet);
            }
        }else if(!player1Cheater && player2Cheater){
                players[0]._address.transfer(players[0].bet);
        }else if(player1Cheater && !player2Cheater){   
                players[1]._address.transfer(players[1].bet);
        }
            
    }
}
