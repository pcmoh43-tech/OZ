from fastapi import FastAPI, APIRouter, UploadFile, File, HTTPException, Form
from fastapi.responses import StreamingResponse
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
import io
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
async def transcribe_audio(
    file: UploadFile = File(...),
    language: str = Form(default="ar")
):
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
    
    # Validate language
    supported_languages = ['ar', 'en', 'auto']
    if language not in supported_languages:
        language = 'ar'
    
    try:
        # Create temporary file
        with tempfile.NamedTemporaryFile(delete=False, suffix=f'.{file_ext}') as tmp_file:
            tmp_file.write(contents)
            tmp_file_path = tmp_file.name
        
        # Prepare transcription options
        transcribe_opts = {
            "file": None,
            "model": "whisper-1",
            "response_format": "json"
        }
        
        # Add language hint (for Arabic dialects like Iraqi, provide context)
        if language == 'ar':
            transcribe_opts["language"] = "ar"
            transcribe_opts["prompt"] = "هذا تسجيل صوتي باللغة العربية، قد يحتوي على لهجات عربية مختلفة مثل اللهجة العراقية أو الخليجية أو المصرية."
        elif language == 'en':
            transcribe_opts["language"] = "en"
        # For 'auto', don't specify language to let Whisper detect
        
        # Transcribe using OpenAI Whisper
        with open(tmp_file_path, "rb") as audio_file:
            transcribe_opts["file"] = audio_file
            response = await stt.transcribe(**transcribe_opts)
        
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


class ExportRequest(BaseModel):
    text: str
    format: str = "txt"  # txt or pdf
    filename: str = "transcription"


@api_router.post("/export")
async def export_text(request: ExportRequest):
    """Export text as TXT or PDF file"""
    
    if request.format == "txt":
        # Create TXT file
        content = request.text.encode('utf-8')
        headers = {
            'Content-Disposition': f'attachment; filename="{request.filename}.txt"',
            'Content-Type': 'text/plain; charset=utf-8'
        }
        return StreamingResponse(
            io.BytesIO(content),
            headers=headers,
            media_type='text/plain'
        )
    
    elif request.format == "pdf":
        try:
            from reportlab.lib.pagesizes import A4
            from reportlab.pdfgen import canvas
            from reportlab.pdfbase import pdfmetrics
            from reportlab.pdfbase.ttfonts import TTFont
            from reportlab.lib.units import inch
            import arabic_reshaper
            from bidi.algorithm import get_display
            
            # Create PDF in memory
            buffer = io.BytesIO()
            c = canvas.Canvas(buffer, pagesize=A4)
            width, height = A4
            
            # Try to use Arabic font
            try:
                # Use a system font that supports Arabic
                pdfmetrics.registerFont(TTFont('Arabic', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
                font_name = 'Arabic'
            except:
                font_name = 'Helvetica'
            
            c.setFont(font_name, 14)
            
            # Process Arabic text for proper RTL display
            try:
                reshaped_text = arabic_reshaper.reshape(request.text)
                bidi_text = get_display(reshaped_text)
            except:
                bidi_text = request.text
            
            # Split text into lines
            lines = bidi_text.split('\n')
            y_position = height - inch
            line_height = 20
            
            for line in lines:
                # Word wrap for long lines
                words = line.split()
                current_line = ""
                
                for word in words:
                    test_line = current_line + " " + word if current_line else word
                    if c.stringWidth(test_line, font_name, 14) < width - 2*inch:
                        current_line = test_line
                    else:
                        if current_line:
                            # Right align for Arabic
                            text_width = c.stringWidth(current_line, font_name, 14)
                            c.drawString(width - inch - text_width, y_position, current_line)
                            y_position -= line_height
                            
                            if y_position < inch:
                                c.showPage()
                                c.setFont(font_name, 14)
                                y_position = height - inch
                        
                        current_line = word
                
                if current_line:
                    text_width = c.stringWidth(current_line, font_name, 14)
                    c.drawString(width - inch - text_width, y_position, current_line)
                    y_position -= line_height
                    
                    if y_position < inch:
                        c.showPage()
                        c.setFont(font_name, 14)
                        y_position = height - inch
            
            c.save()
            buffer.seek(0)
            
            headers = {
                'Content-Disposition': f'attachment; filename="{request.filename}.pdf"',
                'Content-Type': 'application/pdf'
            }
            return StreamingResponse(
                buffer,
                headers=headers,
                media_type='application/pdf'
            )
            
        except ImportError:
            # Fallback to simple text export if PDF libraries not available
            raise HTTPException(
                status_code=500,
                detail="PDF export not available. Please use TXT format."
            )
    
    else:
        raise HTTPException(status_code=400, detail="Unsupported format. Use 'txt' or 'pdf'")

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
