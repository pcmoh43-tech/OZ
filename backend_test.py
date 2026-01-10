import requests
import sys
import json
import tempfile
import os
from datetime import datetime

class SpeechToTextAPITester:
    def __init__(self, base_url="https://call-recorder-18.preview.emergentagent.com"):
        self.base_url = base_url
        self.api_url = f"{base_url}/api"
        self.tests_run = 0
        self.tests_passed = 0
        self.test_results = []

    def log_test(self, name, success, details=""):
        """Log test result"""
        self.tests_run += 1
        if success:
            self.tests_passed += 1
            print(f"✅ {name} - PASSED")
        else:
            print(f"❌ {name} - FAILED: {details}")
        
        self.test_results.append({
            "test": name,
            "success": success,
            "details": details
        })

    def test_api_root(self):
        """Test API root endpoint"""
        try:
            response = requests.get(f"{self.api_url}/", timeout=10)
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            if success:
                data = response.json()
                details += f", Response: {data}"
            self.log_test("API Root Endpoint", success, details)
            return success
        except Exception as e:
            self.log_test("API Root Endpoint", False, str(e))
            return False

    def test_transcriptions_get_empty(self):
        """Test getting transcriptions (should work even if empty)"""
        try:
            response = requests.get(f"{self.api_url}/transcriptions", timeout=10)
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            if success:
                data = response.json()
                details += f", Count: {len(data)} transcriptions"
            self.log_test("Get Transcriptions", success, details)
            return success, response.json() if success else []
        except Exception as e:
            self.log_test("Get Transcriptions", False, str(e))
            return False, []

    def test_save_transcription(self):
        """Test saving a transcription"""
        try:
            test_data = {
                "text": "هذا نص تجريبي للاختبار",
                "original_filename": "test_audio.mp3"
            }
            
            response = requests.post(
                f"{self.api_url}/transcriptions",
                json=test_data,
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            
            if success:
                data = response.json()
                details += f", ID: {data.get('id', 'N/A')}"
                self.log_test("Save Transcription", success, details)
                return success, data.get('id')
            else:
                details += f", Error: {response.text}"
                self.log_test("Save Transcription", success, details)
                return False, None
                
        except Exception as e:
            self.log_test("Save Transcription", False, str(e))
            return False, None

    def test_get_specific_transcription(self, transcription_id):
        """Test getting a specific transcription"""
        if not transcription_id:
            self.log_test("Get Specific Transcription", False, "No transcription ID provided")
            return False
            
        try:
            response = requests.get(f"{self.api_url}/transcriptions/{transcription_id}", timeout=10)
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            
            if success:
                data = response.json()
                details += f", Text: {data.get('text', '')[:50]}..."
            else:
                details += f", Error: {response.text}"
                
            self.log_test("Get Specific Transcription", success, details)
            return success
        except Exception as e:
            self.log_test("Get Specific Transcription", False, str(e))
            return False

    def test_update_transcription(self, transcription_id):
        """Test updating a transcription"""
        if not transcription_id:
            self.log_test("Update Transcription", False, "No transcription ID provided")
            return False
            
        try:
            update_data = {
                "text": "نص محدث للاختبار - تم التعديل"
            }
            
            response = requests.put(
                f"{self.api_url}/transcriptions/{transcription_id}",
                json=update_data,
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            
            if success:
                data = response.json()
                details += f", Updated text: {data.get('text', '')[:50]}..."
            else:
                details += f", Error: {response.text}"
                
            self.log_test("Update Transcription", success, details)
            return success
        except Exception as e:
            self.log_test("Update Transcription", False, str(e))
            return False

    def test_delete_transcription(self, transcription_id):
        """Test deleting a transcription"""
        if not transcription_id:
            self.log_test("Delete Transcription", False, "No transcription ID provided")
            return False
            
        try:
            response = requests.delete(f"{self.api_url}/transcriptions/{transcription_id}", timeout=10)
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            
            if success:
                data = response.json()
                details += f", Message: {data.get('message', 'N/A')}"
            else:
                details += f", Error: {response.text}"
                
            self.log_test("Delete Transcription", success, details)
            return success
        except Exception as e:
            self.log_test("Delete Transcription", False, str(e))
            return False

    def test_transcribe_endpoint_structure(self):
        """Test transcribe endpoint structure (without actual audio file)"""
        try:
            # Test with no file - should return 422 (validation error)
            response = requests.post(f"{self.api_url}/transcribe", timeout=10)
            
            # We expect 422 for missing file, which means endpoint exists
            success = response.status_code == 422
            details = f"Status: {response.status_code} (Expected 422 for missing file)"
            
            if not success and response.status_code == 404:
                details = "Endpoint not found"
            elif not success:
                details += f", Unexpected response: {response.text[:100]}"
                
            self.log_test("Transcribe Endpoint Structure", success, details)
            return success
        except Exception as e:
            self.log_test("Transcribe Endpoint Structure", False, str(e))
            return False

    def test_transcribe_language_parameter(self):
        """Test transcribe endpoint with language parameter (without actual audio)"""
        try:
            # Test with language parameter but no file - should still return 422 but accept the language param
            data = {"language": "ar"}
            response = requests.post(f"{self.api_url}/transcribe", data=data, timeout=10)
            
            # We expect 422 for missing file, but language param should be accepted
            success = response.status_code == 422
            details = f"Status: {response.status_code} (Expected 422 for missing file with language param)"
            
            # Test different language values
            for lang in ["en", "auto"]:
                data = {"language": lang}
                response = requests.post(f"{self.api_url}/transcribe", data=data, timeout=10)
                if response.status_code != 422:
                    success = False
                    details += f", Language '{lang}' failed with status {response.status_code}"
                    break
            
            self.log_test("Transcribe Language Parameter", success, details)
            return success
        except Exception as e:
            self.log_test("Transcribe Language Parameter", False, str(e))
            return False

    def test_export_txt_endpoint(self):
        """Test export TXT endpoint"""
        try:
            test_data = {
                "text": "هذا نص تجريبي للتصدير كملف TXT",
                "format": "txt",
                "filename": "test_export"
            }
            
            response = requests.post(
                f"{self.api_url}/export",
                json=test_data,
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            
            if success:
                # Check if response is a file download
                content_type = response.headers.get('Content-Type', '')
                content_disposition = response.headers.get('Content-Disposition', '')
                details += f", Content-Type: {content_type}, Content-Disposition: {content_disposition}"
                
                # Verify it's a text file download
                if 'text/plain' in content_type and 'attachment' in content_disposition:
                    details += ", Valid TXT export"
                else:
                    success = False
                    details += ", Invalid file response"
            else:
                details += f", Error: {response.text[:100]}"
                
            self.log_test("Export TXT Endpoint", success, details)
            return success
        except Exception as e:
            self.log_test("Export TXT Endpoint", False, str(e))
            return False

    def test_export_pdf_endpoint(self):
        """Test export PDF endpoint"""
        try:
            test_data = {
                "text": "هذا نص تجريبي للتصدير كملف PDF مع دعم النص العربي",
                "format": "pdf",
                "filename": "test_export_pdf"
            }
            
            response = requests.post(
                f"{self.api_url}/export",
                json=test_data,
                headers={"Content-Type": "application/json"},
                timeout=15  # PDF generation might take longer
            )
            
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            
            if success:
                # Check if response is a PDF file download
                content_type = response.headers.get('Content-Type', '')
                content_disposition = response.headers.get('Content-Disposition', '')
                details += f", Content-Type: {content_type}, Content-Disposition: {content_disposition}"
                
                # Verify it's a PDF file download
                if 'application/pdf' in content_type and 'attachment' in content_disposition:
                    details += ", Valid PDF export"
                    # Check if PDF content starts with PDF signature
                    if response.content[:4] == b'%PDF':
                        details += ", Valid PDF format"
                    else:
                        success = False
                        details += ", Invalid PDF format"
                else:
                    success = False
                    details += ", Invalid file response"
            else:
                details += f", Error: {response.text[:100]}"
                
            self.log_test("Export PDF Endpoint", success, details)
            return success
        except Exception as e:
            self.log_test("Export PDF Endpoint", False, str(e))
            return False

    def test_export_invalid_format(self):
        """Test export endpoint with invalid format"""
        try:
            test_data = {
                "text": "Test text",
                "format": "invalid_format",
                "filename": "test"
            }
            
            response = requests.post(
                f"{self.api_url}/export",
                json=test_data,
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            
            # Should return 400 for invalid format
            success = response.status_code == 400
            details = f"Status: {response.status_code} (Expected 400 for invalid format)"
            
            if not success:
                details += f", Unexpected response: {response.text[:100]}"
                
            self.log_test("Export Invalid Format", success, details)
            return success
        except Exception as e:
            self.log_test("Export Invalid Format", False, str(e))
            return False

    def test_mode_status_endpoint(self):
        """Test mode-status endpoint for offline/online availability"""
        try:
            response = requests.get(f"{self.api_url}/mode-status", timeout=10)
            success = response.status_code == 200
            details = f"Status: {response.status_code}"
            
            if success:
                data = response.json()
                online_available = data.get('online_available', False)
                offline_available = data.get('offline_available', False)
                current_mode = data.get('current_mode', 'unknown')
                
                details += f", Online: {online_available}, Offline: {offline_available}, Current: {current_mode}"
                
                # Verify response structure
                if 'online_available' in data and 'offline_available' in data and 'current_mode' in data:
                    details += ", Valid response structure"
                else:
                    success = False
                    details += ", Invalid response structure"
            else:
                details += f", Error: {response.text[:100]}"
                
            self.log_test("Mode Status Endpoint", success, details)
            return success, response.json() if success else {}
        except Exception as e:
            self.log_test("Mode Status Endpoint", False, str(e))
            return False, {}

    def test_transcribe_mode_parameter(self):
        """Test transcribe endpoint with mode parameter (without actual audio)"""
        try:
            # Test different mode values: auto, online, offline
            modes = ["auto", "online", "offline"]
            all_success = True
            details_list = []
            
            for mode in modes:
                data = {"language": "ar", "mode": mode}
                response = requests.post(f"{self.api_url}/transcribe", data=data, timeout=10)
                
                # We expect 422 for missing file, but mode param should be accepted
                mode_success = response.status_code == 422
                mode_details = f"Mode '{mode}': Status {response.status_code}"
                
                if not mode_success:
                    all_success = False
                    mode_details += f" (Expected 422)"
                
                details_list.append(mode_details)
            
            details = ", ".join(details_list)
            self.log_test("Transcribe Mode Parameter", all_success, details)
            return all_success
        except Exception as e:
            self.log_test("Transcribe Mode Parameter", False, str(e))
            return False

    def run_all_tests(self):
        """Run all backend API tests"""
        print("🚀 Starting Speech-to-Text API Tests...")
        print(f"📍 Testing API at: {self.api_url}")
        print("=" * 60)
        
        # Test API availability
        if not self.test_api_root():
            print("❌ API root endpoint failed - stopping tests")
            return self.generate_report()
        
        # Test NEW FEATURE: Mode status endpoint
        mode_success, mode_data = self.test_mode_status_endpoint()
        
        # Test transcribe endpoint structure
        self.test_transcribe_endpoint_structure()
        
        # Test UPDATED FEATURE: Language parameter in transcribe endpoint
        self.test_transcribe_language_parameter()
        
        # Test NEW FEATURE: Mode parameter in transcribe endpoint
        self.test_transcribe_mode_parameter()
        
        # Test EXISTING FEATURE: Export endpoints
        self.test_export_txt_endpoint()
        self.test_export_pdf_endpoint()
        self.test_export_invalid_format()
        
        # Test transcriptions CRUD
        success, existing_transcriptions = self.test_transcriptions_get_empty()
        
        # Test create transcription
        save_success, transcription_id = self.test_save_transcription()
        
        if save_success and transcription_id:
            # Test read specific transcription
            self.test_get_specific_transcription(transcription_id)
            
            # Test update transcription
            self.test_update_transcription(transcription_id)
            
            # Test delete transcription
            self.test_delete_transcription(transcription_id)
        
        return self.generate_report()

    def generate_report(self):
        """Generate test report"""
        print("\n" + "=" * 60)
        print("📊 TEST SUMMARY")
        print("=" * 60)
        print(f"Total Tests: {self.tests_run}")
        print(f"Passed: {self.tests_passed}")
        print(f"Failed: {self.tests_run - self.tests_passed}")
        print(f"Success Rate: {(self.tests_passed/self.tests_run*100):.1f}%" if self.tests_run > 0 else "0%")
        
        if self.tests_passed < self.tests_run:
            print("\n❌ FAILED TESTS:")
            for result in self.test_results:
                if not result["success"]:
                    print(f"  • {result['test']}: {result['details']}")
        
        return {
            "total_tests": self.tests_run,
            "passed_tests": self.tests_passed,
            "failed_tests": self.tests_run - self.tests_passed,
            "success_rate": (self.tests_passed/self.tests_run*100) if self.tests_run > 0 else 0,
            "test_results": self.test_results
        }

def main():
    """Main test execution"""
    tester = SpeechToTextAPITester()
    report = tester.run_all_tests()
    
    # Return appropriate exit code
    return 0 if report["failed_tests"] == 0 else 1

if __name__ == "__main__":
    sys.exit(main())