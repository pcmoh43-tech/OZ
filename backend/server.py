from fastapi import FastAPI, APIRouter, UploadFile, File, HTTPException
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import os
import logging
from pathlib import Path
from pydantic import BaseModel, Field, ConfigDict
from typing import List, Optional
import uuid
from datetime import datetime, timezone
import tempfile
from emergentintegrations.llm.openai import OpenAISpeechToText

ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')

# MongoDB connection
mongo_url = os.environ['MONGO_URL']
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ['DB_NAME']]

# Create the main app without a prefix
app = FastAPI()

# Create a router with the /api prefix
api_router = APIRouter(prefix="/api")

# Initialize Speech-to-Text
stt = OpenAISpeechToText(api_key=os.getenv("EMERGENT_LLM_KEY"))

# Define Models
class Transcription(BaseModel):
    model_config = ConfigDict(extra="ignore")
    
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    text: str
    original_filename: Optional[str] = None
    duration: Optional[float] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class TranscriptionCreate(BaseModel):
    text: str
    original_filename: Optional[str] = None

class TranscriptionUpdate(BaseModel):
    text: str

class TranscribeResponse(BaseModel):
    text: str
    filename: str

# Routes
@api_router.get("/")
async def root():
    return {"message": "Speech to Text API"}

@api_router.post("/transcribe", response_model=TranscribeResponse)
async def transcribe_audio(file: UploadFile = File(...)):
    """Transcribe audio file to text using OpenAI Whisper"""
    
    # Validate file type
    allowed_extensions = ['mp3', 'mp4', 'mpeg', 'mpga', 'm4a', 'wav', 'webm', 'ogg']
    file_ext = file.filename.split('.')[-1].lower() if file.filename else ''
    
    if file_ext not in allowed_extensions:
        raise HTTPException(
            status_code=400, 
            detail=f"Unsupported file format. Allowed: {', '.join(allowed_extensions)}"
        )
    
    # Check file size (25MB limit)
    contents = await file.read()
    if len(contents) > 25 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File size exceeds 25MB limit")
    
    try:
        # Create temporary file
        with tempfile.NamedTemporaryFile(delete=False, suffix=f'.{file_ext}') as tmp_file:
            tmp_file.write(contents)
            tmp_file_path = tmp_file.name
        
        # Transcribe using OpenAI Whisper
        with open(tmp_file_path, "rb") as audio_file:
            response = await stt.transcribe(
                file=audio_file,
                model="whisper-1",
                language="ar",  # Arabic language
                response_format="json"
            )
        
        # Cleanup temp file
        os.unlink(tmp_file_path)
        
        return TranscribeResponse(
            text=response.text,
            filename=file.filename or "audio"
        )
        
    except Exception as e:
        logger.error(f"Transcription error: {str(e)}")
        # Cleanup temp file on error
        if 'tmp_file_path' in locals():
            try:
                os.unlink(tmp_file_path)
            except:
                pass
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

@api_router.post("/transcriptions", response_model=Transcription)
async def save_transcription(input: TranscriptionCreate):
    """Save a transcription to the database"""
    transcription = Transcription(**input.model_dump())
    
    doc = transcription.model_dump()
    doc['created_at'] = doc['created_at'].isoformat()
    
    await db.transcriptions.insert_one(doc)
    return transcription

@api_router.get("/transcriptions", response_model=List[Transcription])
async def get_transcriptions():
    """Get all saved transcriptions"""
    transcriptions = await db.transcriptions.find({}, {"_id": 0}).sort("created_at", -1).to_list(100)
    
    for t in transcriptions:
        if isinstance(t['created_at'], str):
            t['created_at'] = datetime.fromisoformat(t['created_at'])
    
    return transcriptions

@api_router.get("/transcriptions/{transcription_id}", response_model=Transcription)
async def get_transcription(transcription_id: str):
    """Get a specific transcription"""
    transcription = await db.transcriptions.find_one({"id": transcription_id}, {"_id": 0})
    
    if not transcription:
        raise HTTPException(status_code=404, detail="Transcription not found")
    
    if isinstance(transcription['created_at'], str):
        transcription['created_at'] = datetime.fromisoformat(transcription['created_at'])
    
    return transcription

@api_router.put("/transcriptions/{transcription_id}", response_model=Transcription)
async def update_transcription(transcription_id: str, input: TranscriptionUpdate):
    """Update a transcription"""
    result = await db.transcriptions.update_one(
        {"id": transcription_id},
        {"$set": {"text": input.text}}
    )
    
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Transcription not found")
    
    return await get_transcription(transcription_id)

@api_router.delete("/transcriptions/{transcription_id}")
async def delete_transcription(transcription_id: str):
    """Delete a transcription"""
    result = await db.transcriptions.delete_one({"id": transcription_id})
    
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Transcription not found")
    
    return {"message": "Transcription deleted successfully"}

# Include the router in the main app
app.include_router(api_router)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=os.environ.get('CORS_ORIGINS', '*').split(','),
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()
