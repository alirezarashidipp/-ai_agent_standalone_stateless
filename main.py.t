import json
from typing import Any, Dict
from state import GroomingSession
from graph import app

def run_agent_step(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Stateless Logic Controller:
    Reconstructs the session from the payload, executes the graph, 
    and returns the updated state to the client.
    """
    
    session_data = payload.get("session", {})
    user_message = payload.get("message", "").strip()
    
    try:
        # Reconstruct Pydantic model from incoming dictionary
        session = GroomingSession(**session_data)
        
        # Inject current request context into the state
        session.last_user_message = user_message
        
        # Stateless Invoke: Graph starts from START and routes via 'phase'
        print(f"[SYSTEM] Processing current phase: {session.phase}")
        final_state_output = app.invoke(session)
        
        # LangGraph returns a dict or the model depending on configuration
        # Ensuring we have a valid GroomingSession object for serialization
        if isinstance(final_state_output, dict):
            updated_session = GroomingSession(**final_state_output)
        else:
            updated_session = final_state_output

        # Serialization for transmission back to client (K8s / Spyder)
        return {
            "session": updated_session.model_dump(),
            "status": "success",
            "message": _get_display_text(updated_session)
        }

    except Exception as e:
        print(f"[FATAL] Pipeline Execution Error: {e}")
        return {
            "session": session_data,
            "status": "error",
            "error_detail": str(e)
        }

def _get_display_text(session: GroomingSession) -> str:
    """
    Helper to determine the UI message based on the session's resulting phase.
    """
    phase_messages = {
        "clarifying": "I need more details. Please answer the missing fields.",
        "reviewing_ac": "The Acceptance Criteria are ready for review. Type 'confirm' to finish.",
        "done": "The Jira Story has been generated successfully.",
    }
    return phase_messages.get(session.phase, "Analyzing requirements...")

if __name__ == "__main__":
    # Local Simulation for Spyder environment
    mock_payload = {
        "session": {}, 
        "message": "I want to implement a dual-factor authentication system."
    }
    
    result = run_agent_step(mock_payload)
    print(json.dumps(result, indent=2))
