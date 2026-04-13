import openai
import base64
import json
import fitz
import sys
from pathlib import Path

client = openai.OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-local-master-1234"
)

SCHEMA = {
    "document_type": "string",
    "date": "string or null",
    "sender": {
        "name": "string or null",
        "organization": "string or null",
        "address": "string or null"
    },
    "recipient": "string or null",
    "subject": "string or null",
    "key_points": ["string"],
    "contact_info": {
        "phone": "string or null",
        "fax": "string or null",
        "email": "string or null"
    }
}

def page_to_base64(page, dpi=150):
    pix = page.get_pixmap(dpi=dpi)
    return base64.b64encode(pix.tobytes("png")).decode()

def extract_page(img_b64, page_num):
    print(f"  Processing page {page_num + 1}...")
    response = client.chat.completions.create(
        model="pdf-vision",
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/png;base64,{img_b64}"}
                },
                {
                    "type": "text",
                    "text": (
                        "Extract information from this scanned document page and return ONLY valid JSON "
                        "matching this schema. Use null for fields you cannot find. No explanation, no markdown:\n\n"
                        + json.dumps(SCHEMA, indent=2)
                    )
                }
            ]
        }],
        max_tokens=1024
    )
    raw = response.choices[0].message.content.strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    return json.loads(raw.strip())

def process_pdf(pdf_path):
    doc = fitz.open(pdf_path)
    print(f"PDF: {pdf_path} ({len(doc)} pages)")
    results = []
    for i, page in enumerate(doc):
        img_b64 = page_to_base64(page)
        try:
            data = extract_page(img_b64, i)
            results.append({"page": i + 1, "data": data})
            print(f"  ✓ Page {i + 1} extracted")
            print(json.dumps(data, indent=2))
        except json.JSONDecodeError as e:
            print(f"  ✗ Page {i + 1} JSON parse failed: {e}")
            results.append({"page": i + 1, "error": "JSON parse failed"})
        except Exception as e:
            print(f"  ✗ Page {i + 1} failed: {e}")
            results.append({"page": i + 1, "error": str(e)})
    return results

if __name__ == "__main__":
    pdf_path = sys.argv[1] if len(sys.argv) > 1 else "sample_scanned.pdf"
    results = process_pdf(pdf_path)
    out_path = Path(pdf_path).stem + "_extracted.json"
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved to {out_path}")
