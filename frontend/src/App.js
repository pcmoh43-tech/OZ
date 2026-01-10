import { useState, useRef, useEffect, useCallback } from "react";
import "@/App.css";
import axios from "axios";
import { Toaster, toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Mic,
  Square,
  Upload,
  Copy,
  Check,
  Trash2,
  Moon,
  Sun,
  FileAudio,
  History,
  Save,
  Loader2,
  Volume2,
  Download,
  FileText,
  FileType,
  Languages,
} from "lucide-react";

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL;
const API = `${BACKEND_URL}/api`;

// Arabic punctuation marks
const PUNCTUATION_MARKS = [
  { label: "،", name: "فاصلة" },
  { label: ".", name: "نقطة" },
  { label: "؟", name: "استفهام" },
  { label: "!", name: "تعجب" },
  { label: ":", name: "نقطتان" },
  { label: "؛", name: "فاصلة منقوطة" },
  { label: "(", name: "قوس فتح" },
  { label: ")", name: "قوس إغلاق" },
  { label: "«", name: "تنصيص فتح" },
  { label: "»", name: "تنصيص إغلاق" },
  { label: "-", name: "شرطة" },
  { label: "...", name: "حذف" },
];

// Language options
const LANGUAGES = [
  { value: "ar", label: "العربية", icon: "🇸🇦" },
  { value: "en", label: "English", icon: "🇺🇸" },
  { value: "auto", label: "تلقائي", icon: "🌐" },
];

function App() {
  const [text, setText] = useState("");
  const [isRecording, setIsRecording] = useState(false);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [isDarkMode, setIsDarkMode] = useState(false);
  const [copied, setCopied] = useState(false);
  const [history, setHistory] = useState([]);
  const [showHistory, setShowHistory] = useState(false);
  const [dragOver, setDragOver] = useState(false);
  const [selectedLanguage, setSelectedLanguage] = useState("ar");
  const [isExporting, setIsExporting] = useState(false);
  
  const textareaRef = useRef(null);
  const mediaRecorderRef = useRef(null);
  const audioChunksRef = useRef([]);
  const fileInputRef = useRef(null);

  // Load history on mount
  useEffect(() => {
    fetchHistory();
  }, []);

  // Apply dark mode
  useEffect(() => {
    if (isDarkMode) {
      document.documentElement.classList.add("dark");
    } else {
      document.documentElement.classList.remove("dark");
    }
  }, [isDarkMode]);

  const fetchHistory = async () => {
    try {
      const response = await axios.get(`${API}/transcriptions`);
      setHistory(response.data);
    } catch (error) {
      console.error("Error fetching history:", error);
    }
  };

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream, { mimeType: "audio/webm" });
      mediaRecorderRef.current = mediaRecorder;
      audioChunksRef.current = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          audioChunksRef.current.push(event.data);
        }
      };

      mediaRecorder.onstop = async () => {
        const audioBlob = new Blob(audioChunksRef.current, { type: "audio/webm" });
        stream.getTracks().forEach((track) => track.stop());
        await transcribeAudio(audioBlob, "recording.webm");
      };

      mediaRecorder.start();
      setIsRecording(true);
      toast.success("بدأ التسجيل...");
    } catch (error) {
      console.error("Error starting recording:", error);
      toast.error("فشل في الوصول للميكروفون");
    }
  };

  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      setIsRecording(false);
    }
  };

  const transcribeAudio = async (audioBlob, filename) => {
    setIsTranscribing(true);
    
    try {
      const formData = new FormData();
      formData.append("file", audioBlob, filename);
      formData.append("language", selectedLanguage);

      const response = await axios.post(`${API}/transcribe`, formData, {
        headers: { "Content-Type": "multipart/form-data" },
      });

      const newText = text ? `${text}\n\n${response.data.text}` : response.data.text;
      setText(newText);
      toast.success("تم التحويل بنجاح!");
    } catch (error) {
      console.error("Transcription error:", error);
      const errorMsg = error.response?.data?.detail || "فشل في تحويل الصوت";
      toast.error(errorMsg);
    } finally {
      setIsTranscribing(false);
    }
  };

  const handleFileUpload = async (file) => {
    if (!file) return;
    
    const fileExt = file.name.split(".").pop().toLowerCase();
    const allowedExts = ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm", "ogg"];
    
    if (!allowedExts.includes(fileExt)) {
      toast.error("صيغة الملف غير مدعومة");
      return;
    }

    if (file.size > 25 * 1024 * 1024) {
      toast.error("حجم الملف يتجاوز 25 ميجابايت");
      return;
    }

    await transcribeAudio(file, file.name);
  };

  const handleDrop = useCallback((e) => {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files[0];
    if (file) handleFileUpload(file);
  }, [selectedLanguage]);

  const handleDragOver = useCallback((e) => {
    e.preventDefault();
    setDragOver(true);
  }, []);

  const handleDragLeave = useCallback((e) => {
    e.preventDefault();
    setDragOver(false);
  }, []);

  const insertPunctuation = (mark) => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const newText = text.substring(0, start) + mark + text.substring(end);
    
    setText(newText);
    
    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(start + mark.length, start + mark.length);
    }, 0);
  };

  const copyToClipboard = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      toast.success("تم النسخ!");
      setTimeout(() => setCopied(false), 2000);
    } catch (error) {
      toast.error("فشل في النسخ");
    }
  };

  const saveTranscription = async () => {
    if (!text.trim()) {
      toast.error("لا يوجد نص للحفظ");
      return;
    }

    try {
      await axios.post(`${API}/transcriptions`, {
        text: text.trim(),
        original_filename: "manual_entry",
      });
      toast.success("تم الحفظ!");
      fetchHistory();
    } catch (error) {
      toast.error("فشل في الحفظ");
    }
  };

  const exportText = async (format) => {
    if (!text.trim()) {
      toast.error("لا يوجد نص للتصدير");
      return;
    }

    setIsExporting(true);
    
    try {
      const response = await axios.post(
        `${API}/export`,
        {
          text: text.trim(),
          format: format,
          filename: `transcription_${new Date().toISOString().slice(0, 10)}`,
        },
        { responseType: 'blob' }
      );

      // Create download link
      const blob = new Blob([response.data], { 
        type: format === 'pdf' ? 'application/pdf' : 'text/plain' 
      });
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `transcription_${new Date().toISOString().slice(0, 10)}.${format}`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(url);
      
      toast.success(`تم تصدير الملف بصيغة ${format.toUpperCase()}`);
    } catch (error) {
      console.error("Export error:", error);
      toast.error("فشل في التصدير");
    } finally {
      setIsExporting(false);
    }
  };

  const loadFromHistory = (item) => {
    setText(item.text);
    setShowHistory(false);
    toast.success("تم تحميل النص");
  };

  const deleteFromHistory = async (id, e) => {
    e.stopPropagation();
    try {
      await axios.delete(`${API}/transcriptions/${id}`);
      toast.success("تم الحذف");
      fetchHistory();
    } catch (error) {
      toast.error("فشل في الحذف");
    }
  };

  const clearText = () => {
    setText("");
    toast.success("تم المسح");
  };

  return (
    <div className="app-container min-h-screen bg-[#fdfbf7] dark:bg-[#0f172a]" dir="rtl">
      <Toaster position="top-center" richColors />
      
      {/* Header */}
      <header className="sticky top-0 z-50 glass border-b border-slate-200 dark:border-slate-800">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-amber-500 flex items-center justify-center">
                <Volume2 className="w-5 h-5 text-white" />
              </div>
              <div>
                <h1 className="text-xl font-bold text-slate-900 dark:text-white" data-testid="app-title">
                  تحويل الصوت إلى نص
                </h1>
                <p className="text-sm text-slate-500 dark:text-slate-400">
                  حوّل تسجيلاتك الصوتية إلى نص مكتوب
                </p>
              </div>
            </div>
            
            <div className="flex items-center gap-2">
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setShowHistory(!showHistory)}
                className="rounded-full"
                data-testid="history-toggle-btn"
              >
                <History className="w-5 h-5" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setIsDarkMode(!isDarkMode)}
                className="rounded-full"
                data-testid="theme-toggle-btn"
              >
                {isDarkMode ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
              </Button>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
          
          {/* Sidebar - Audio Input */}
          <div className="lg:col-span-4 flex flex-col gap-6">
            
            {/* Language Selection Card */}
            <Card className="p-6 bg-white dark:bg-slate-800 border-slate-100 dark:border-slate-700 shadow-[0_4px_20px_-2px_rgba(0,0,0,0.05)]">
              <div className="flex items-center gap-2 mb-4">
                <Languages className="w-5 h-5 text-amber-500" />
                <h2 className="text-lg font-semibold text-slate-900 dark:text-white">
                  لغة التسجيل
                </h2>
              </div>
              
              <Select value={selectedLanguage} onValueChange={setSelectedLanguage}>
                <SelectTrigger className="w-full" data-testid="language-select">
                  <SelectValue placeholder="اختر اللغة" />
                </SelectTrigger>
                <SelectContent>
                  {LANGUAGES.map((lang) => (
                    <SelectItem key={lang.value} value={lang.value}>
                      <span className="flex items-center gap-2">
                        <span>{lang.icon}</span>
                        <span>{lang.label}</span>
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              
              {selectedLanguage === "ar" && (
                <p className="text-xs text-slate-500 dark:text-slate-400 mt-2">
                  يدعم جميع اللهجات العربية (العراقية، الخليجية، المصرية، الشامية)
                </p>
              )}
            </Card>

            {/* Record Card */}
            <Card className="p-6 bg-white dark:bg-slate-800 border-slate-100 dark:border-slate-700 shadow-[0_4px_20px_-2px_rgba(0,0,0,0.05)]">
              <h2 className="text-lg font-semibold text-slate-900 dark:text-white mb-4">
                تسجيل صوتي
              </h2>
              
              <div className="flex flex-col items-center gap-4">
                <button
                  onClick={isRecording ? stopRecording : startRecording}
                  disabled={isTranscribing}
                  className={`record-btn w-20 h-20 rounded-full flex items-center justify-center transition-all ${
                    isRecording 
                      ? "bg-red-500 recording" 
                      : "bg-amber-500 hover:bg-amber-600"
                  } ${isTranscribing ? "opacity-50 cursor-not-allowed" : ""}`}
                  data-testid="record-btn"
                >
                  {isRecording ? (
                    <Square className="w-8 h-8 text-white fill-white" />
                  ) : (
                    <Mic className="w-8 h-8 text-white" />
                  )}
                </button>
                
                <p className="text-sm text-slate-500 dark:text-slate-400">
                  {isRecording ? "جاري التسجيل... اضغط للإيقاف" : "اضغط للتسجيل"}
                </p>
              </div>
            </Card>

            {/* Upload Card */}
            <Card className="p-6 bg-white dark:bg-slate-800 border-slate-100 dark:border-slate-700 shadow-[0_4px_20px_-2px_rgba(0,0,0,0.05)]">
              <h2 className="text-lg font-semibold text-slate-900 dark:text-white mb-4">
                رفع ملف صوتي
              </h2>
              
              <div
                onClick={() => fileInputRef.current?.click()}
                onDrop={handleDrop}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                className={`upload-zone rounded-xl p-8 flex flex-col items-center gap-3 cursor-pointer ${
                  dragOver ? "drag-over" : ""
                }`}
                data-testid="upload-zone"
              >
                <div className="w-12 h-12 rounded-full bg-slate-100 dark:bg-slate-700 flex items-center justify-center">
                  <Upload className="w-6 h-6 text-slate-400" />
                </div>
                <div className="text-center">
                  <p className="text-sm font-medium text-slate-700 dark:text-slate-300">
                    اسحب الملف هنا أو اضغط للاختيار
                  </p>
                  <p className="text-xs text-slate-400 mt-1">
                    MP3, WAV, M4A, WebM (حتى 25 ميجابايت)
                  </p>
                </div>
              </div>
              
              <input
                ref={fileInputRef}
                type="file"
                accept=".mp3,.wav,.m4a,.webm,.mp4,.ogg,.mpeg,.mpga"
                onChange={(e) => handleFileUpload(e.target.files[0])}
                className="hidden"
                data-testid="file-input"
              />
            </Card>

            {/* History Panel */}
            {showHistory && (
              <Card className="p-4 bg-white dark:bg-slate-800 border-slate-100 dark:border-slate-700 shadow-[0_4px_20px_-2px_rgba(0,0,0,0.05)]">
                <h2 className="text-lg font-semibold text-slate-900 dark:text-white mb-3 px-2">
                  السجل
                </h2>
                
                <ScrollArea className="h-64">
                  {history.length === 0 ? (
                    <p className="text-sm text-slate-400 text-center py-8">
                      لا يوجد سجل بعد
                    </p>
                  ) : (
                    <div className="space-y-2">
                      {history.map((item) => (
                        <div
                          key={item.id}
                          onClick={() => loadFromHistory(item)}
                          className="history-item p-3 rounded-lg cursor-pointer group"
                          data-testid={`history-item-${item.id}`}
                        >
                          <div className="flex items-start justify-between gap-2">
                            <div className="flex-1 min-w-0">
                              <p className="text-sm text-slate-700 dark:text-slate-300 truncate">
                                {item.text.substring(0, 50)}...
                              </p>
                              <p className="text-xs text-slate-400 mt-1">
                                {new Date(item.created_at).toLocaleDateString("ar-SA")}
                              </p>
                            </div>
                            <Button
                              variant="ghost"
                              size="icon"
                              onClick={(e) => deleteFromHistory(item.id, e)}
                              className="opacity-0 group-hover:opacity-100 h-8 w-8"
                              data-testid={`delete-history-${item.id}`}
                            >
                              <Trash2 className="w-4 h-4 text-red-500" />
                            </Button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </ScrollArea>
              </Card>
            )}
          </div>

          {/* Editor Area */}
          <div className="lg:col-span-8 flex flex-col">
            <Card className="flex-1 flex flex-col bg-white dark:bg-slate-800 border-slate-100 dark:border-slate-700 shadow-[0_4px_20px_-2px_rgba(0,0,0,0.05)] overflow-hidden">
              
              {/* Editor Header */}
              <div className="flex items-center justify-between p-4 border-b border-slate-100 dark:border-slate-700">
                <div className="flex items-center gap-2">
                  <FileAudio className="w-5 h-5 text-slate-400" />
                  <span className="text-sm font-medium text-slate-700 dark:text-slate-300">
                    النص المحوّل
                  </span>
                </div>
                
                <div className="flex items-center gap-2">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={clearText}
                    disabled={!text}
                    className="text-slate-500 hover:text-red-500"
                    data-testid="clear-btn"
                  >
                    <Trash2 className="w-4 h-4 ml-1" />
                    مسح
                  </Button>
                  
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={saveTranscription}
                    disabled={!text}
                    className="text-slate-500 hover:text-green-500"
                    data-testid="save-btn"
                  >
                    <Save className="w-4 h-4 ml-1" />
                    حفظ
                  </Button>

                  {/* Export Dropdown */}
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={!text || isExporting}
                        className="text-slate-500 hover:text-blue-500"
                        data-testid="export-btn"
                      >
                        {isExporting ? (
                          <Loader2 className="w-4 h-4 ml-1 animate-spin" />
                        ) : (
                          <Download className="w-4 h-4 ml-1" />
                        )}
                        تصدير
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onClick={() => exportText('txt')} data-testid="export-txt">
                        <FileText className="w-4 h-4 ml-2" />
                        تصدير كـ TXT
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={() => exportText('pdf')} data-testid="export-pdf">
                        <FileType className="w-4 h-4 ml-2" />
                        تصدير كـ PDF
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                  
                  <Button
                    variant="default"
                    size="sm"
                    onClick={copyToClipboard}
                    disabled={!text}
                    className="bg-primary hover:bg-primary/90"
                    data-testid="copy-btn"
                  >
                    {copied ? (
                      <>
                        <Check className="w-4 h-4 ml-1" />
                        تم النسخ
                      </>
                    ) : (
                      <>
                        <Copy className="w-4 h-4 ml-1" />
                        نسخ
                      </>
                    )}
                  </Button>
                </div>
              </div>

              {/* Loading State */}
              {isTranscribing && (
                <div className="flex items-center justify-center gap-3 py-4 bg-amber-50 dark:bg-amber-900/20">
                  <Loader2 className="w-5 h-5 text-amber-500 animate-spin" />
                  <span className="text-sm text-amber-700 dark:text-amber-400">
                    جاري التحويل...
                  </span>
                </div>
              )}

              {/* Text Editor */}
              <div className="flex-1 p-6 relative min-h-[400px]">
                {!text && !isTranscribing && (
                  <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                    <div className="text-center">
                      <div className="w-16 h-16 rounded-full bg-slate-100 dark:bg-slate-700 flex items-center justify-center mx-auto mb-4">
                        <Mic className="w-8 h-8 text-slate-300 dark:text-slate-500" />
                      </div>
                      <p className="text-slate-400 dark:text-slate-500">
                        سجّل صوتك أو ارفع ملف صوتي للبدء
                      </p>
                    </div>
                  </div>
                )}
                
                <textarea
                  ref={textareaRef}
                  value={text}
                  onChange={(e) => setText(e.target.value)}
                  placeholder="سيظهر النص المحوّل هنا..."
                  className="editor-textarea"
                  data-testid="text-editor"
                />
              </div>

              {/* Punctuation Toolbar */}
              <div className="punctuation-toolbar p-4 sticky bottom-0">
                <div className="flex items-center gap-2 overflow-x-auto pb-2">
                  <span className="text-sm text-slate-500 dark:text-slate-400 whitespace-nowrap ml-2">
                    علامات الترقيم:
                  </span>
                  
                  <div className="flex items-center gap-2">
                    {PUNCTUATION_MARKS.map((mark) => (
                      <button
                        key={mark.label}
                        onClick={() => insertPunctuation(mark.label)}
                        className="punct-btn"
                        title={mark.name}
                        data-testid={`punct-${mark.name}`}
                      >
                        {mark.label}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            </Card>

            {/* Character Count */}
            {text && (
              <div className="mt-3 text-left">
                <span className="text-sm text-slate-400">
                  {text.length} حرف • {text.split(/\s+/).filter(Boolean).length} كلمة
                </span>
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;
