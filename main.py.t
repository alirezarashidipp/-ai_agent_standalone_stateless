import json
from typing import Any, Dict
from state import GroomingSession
from graph import app

def run_agent_step(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    The core controller for stateless execution.
    
    Args:
        payload: A dictionary containing:
            - "session": The last known state (JSON-compatible dict).
            - "message": The new user input string.
            
    Returns:
        A dictionary containing the updated session state.
    """
    
    # 1. Extraction: Load state from the provided dictionary
    # If 'session' is empty/None, Pydantic initializes with default values (Phase.START)
    session_data = payload.get("session", {})
    user_message = payload.get("message", "").strip()
    
    try:
        session = GroomingSession(**session_data)
        
        # 2. Update: Inject the new user message into the state
        session.last_user_message = user_message
        
        # 3. Execution: Invoke the stateless LangGraph
        # The graph will route based on session.phase and run exactly ONE node
        print(f"--- Processing Phase: {session.phase} ---")
        final_state_dict = app.invoke(session)
        
        # 4. Serialization: Convert the result back to a plain dictionary
        # This dictionary is what you send back to the client/frontend
        return {
            "session": final_state_dict.model_dump(),
            "status": "success"
        }

    except Exception as e:
        print(f"[ERROR] Failed to process agent step: {e}")
        return {
            "session": session_data,
            "status": "error",
            "error_message": str(e)
        }

# --- Example Usage (Simulation of a Chat Loop) ---
if __name__ == "__main__":
    # Start with an empty session
    current_payload = {
        "session": {},
        "message": "I want a new login page for the mobile app."
    }
    
    # Step 1: Initial Extraction
    response = run_agent_step(current_payload)
    print(f"New Phase: {response['session']['phase']}")
    
    # Simulate the client sending the state back with a new message
    next_payload = {
        "session": response["session"],
        "message": "It's for the Android version specifically."
    }
    
    # Step 2: Next step in the graph
    response = run_agent_step(next_payload)
    print(f"Final Phase: {response['session']['phase']}")
