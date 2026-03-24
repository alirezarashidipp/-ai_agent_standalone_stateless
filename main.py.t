import json
from typing import Any, Dict
from state import GroomingSession
from graph import app

def run_agent_step(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Stateless entry point. 
    Receives JSON payload, executes logic, and returns updated state.
    """
    
    session_data = payload.get("session", {})
    user_message = payload.get("message", "").strip()
    
    try:
        # Reconstruct session model from raw dictionary
        # If session_data is empty, Pydantic handles default values (Phase.START)
        session = GroomingSession(**session_data)
        
        # Inject the new user context into the state
        session.last_user_message = user_message
        
        # Execute LangGraph (Stateless Invoke)
        # The graph starts from START and routes to the correct node via 'phase'
        print(f"[SYSTEM] Orchestrating execution for phase: {session.phase}")
        final_state_output = app.invoke(session)
        
        # Ensure the output is converted back to a validated Pydantic model
        if isinstance(final_state_output, dict):
            updated_session = GroomingSession(**final_state_output)
        else:
            updated_session = final_state_output

        # Serialization for return to Client (K8s or Local)
        return {
            "session": updated_session.model_dump(),
            "status": "success",
            "feedback": _generate_ui_feedback(updated_session)
        }

    except Exception as e:
        print(f"[FATAL] Runtime Error: {e}")
        return {
            "session": session_data,
            "status": "error",
            "error_detail": str(e)
        }

def _generate_ui_feedback(session: GroomingSession) -> str:
    """
    Helper function to map the internal phase to a human-readable UI message.
    """
    feedback_map = {
        "clarifying": "Requirement incomplete. Please answer the clarification questions.",
        "refining_tech": "Analyzing technical feasibility. Please wait for specific tech lead questions.",
        "reviewing_ac": "Draft Acceptance Criteria generated. Type 'confirm' or suggest edits.",
        "done": "Grooming complete. Your Jira Story is ready for export."
    }
    return feedback_map.get(session.phase, "Processing your request...")

if __name__ == "__main__":
    # Local simulation for Spyder testing
    mock_input = {
        "session": {}, 
        "message": "As a user, I want to reset my password using my phone number."
    }
    
    result = run_agent_step(mock_input)
    print(json.dumps(result, indent=2))
