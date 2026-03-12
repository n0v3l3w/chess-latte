# **Chess\! Script for Matcha** 

A Python-powered FastAPI server that bridges the **Stockfish** engine with Matcha for real-time move calculation.

## **Features**

* **Stockfish Integration**: Uses the UCI protocol to communicate with the world's strongest chess engine.  
* **Auto-Configuration**: Built-in prompts to optimize Hash, Threads, and Syzygy Tablebases based on your PC specs.  
* **FastAPI Backend**: Runs a local server on port 3000 to handle move requests instantly.

## **Setup & Installation**

## **1\. Prerequisites**

* **Python 3.7+**: [Download here](https://www.python.org/downloads/)  
* **Stockfish Binary**: [Download here](https://stockfishchess.org/download/)

## **2\. Install Dependencies**

Open your terminal or command prompt in the project folder and run:

`pip install -r requirements.txt`

## **3\. Running the Script**

1. Launch the script:  
   `python main.py`

2. **Select Stockfish**: A file picker will appear. Select your downloaded Stockfish executable (.exe on Windows).  
3. **Configure Engine**: You will be prompted for Hash and Thread counts. You can press **Enter** to leave these at default.  
4. **Server Ready**: Once you see Server started at http://localhost:3000, the script is ready to work.

## **How to Use with Matcha**

* `loadstring(game:HttpGet("https://raw.githubusercontent.com/n0v3l3w/chess-latte/refs/heads/main/chess-latte-script.lua"))()`
* **Default Keybind**: The calculation is typically triggered by **R** by default.  
* ⚠️ **Important**: Do not press the calculate button too early\! Wait for the board to fully update after a move is made before requesting a calculation to ensure accuracy.

## **Contributing**

Pull requests are welcome\! Feel free to submit improvements.
