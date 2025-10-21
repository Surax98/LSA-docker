#!/usr/bin/env python3
"""
Auto-detect latest LSA version from Broadcom's JavaScript-rendered download page.

USAGE:
    python3 get_latest_version.py
    LSA_VERSION=008.014.012.000_MR7.34 python3 get_latest_version.py

REQUIREMENTS:
    pip install selenium
    Chrome + ChromeDriver (or Firefox + GeckoDriver)
"""

import os
import sys
import re
import urllib.request
import urllib.error
import time
from typing import Union, List

# Configuration
BASEURL = "https://docs.broadcom.com/docs-and-downloads"
SEARCH_URL = "https://www.broadcom.com/support/download-search?pg=&pf=Storage+Adapters,+Controllers,+and+ICs&pn=&pa=&po=&dk=Latest+LSA+for+Linux&pl=&l=false"
FALLBACK_VERSION = "008.014.012.000_MR7.34"
PAGE_WAIT = 10  # Seconds for JavaScript to load


def log(msg: str, end: str = '\n') -> None:
    """Log to stderr, keeping stdout clean for version output."""
    print(msg, end=end, file=sys.stderr, flush=True)


def validate_version(version: str) -> bool:
    """Check if version exists on download server."""
    if not re.match(r'\d{3}\.\d{3}\.\d{3}\.\d{3}_MR\d+\.\d+', version):
        return False
    
    url = f"{BASEURL}/{version}_LSA_Linux.zip"
    try:
        req = urllib.request.Request(url, method='HEAD')
        req.add_header('User-Agent', 'Mozilla/5.0')
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status == 200
    except:
        return False


def get_chrome_driver():
    """Initialize headless Chrome driver."""
    try:
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.chrome.service import Service
        import shutil
        
        options = Options()
        for arg in ['--headless=new', '--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu']:
            options.add_argument(arg)
        
        # Try common chromedriver locations
        for path in ['/usr/local/bin/chromedriver', '/usr/bin/chromedriver', shutil.which('chromedriver')]:
            if path and os.path.exists(path):
                log(f"Using chromedriver: {path}")
                return webdriver.Chrome(service=Service(path), options=options)
        
        # Let Selenium find it
        return webdriver.Chrome(options=options)
    except Exception as e:
        log(f"Chrome driver failed: {e}")
        return None


def scrape_versions() -> Union[str, List[str], None]:
    """Scrape Broadcom page and extract version candidates."""
    log("Scraping with Selenium...")
    
    try:
        from selenium import webdriver
    except ImportError:
        log("ERROR: Selenium not installed (pip install selenium)")
        return None
    
    driver = get_chrome_driver()
    if not driver:
        return None
    
    try:
        log(f"Loading: {SEARCH_URL}")
        driver.get(SEARCH_URL)
        time.sleep(PAGE_WAIT)
        
        page = driver.page_source
        log(f"Page loaded: {len(page)} chars")
        
        # Try to find complete version first
        complete = re.findall(r'(\d{3}\.\d{3}\.\d{3}\.\d{3}_MR\d+\.\d+)', page)
        if complete:
            log(f"Found complete version: {complete[0]}")
            return complete[0]
        
        # Extract and combine parts
        bases = re.findall(r'(\d{3}\.\d{3}\.\d{3}\.\d{3})', page)
        mrs = re.findall(r'MR\s*(\d+)\.(\d+)', page, re.I)
        
        if not (bases and mrs):
            log("No version components found")
            return None
        
        # Get highest base version
        base = sorted(set(bases), key=lambda v: tuple(map(int, v.split('.'))), reverse=True)[0]
        # Sort MR versions (highest first)
        mrs_sorted = sorted(set(mrs), key=lambda v: (int(v[0]), int(v[1])), reverse=True)
        
        log(f"Base: {base}, MRs: {[f'{m[0]}.{m[1]}' for m in mrs_sorted]}")
        
        # Build candidates
        candidates = [f"{base}_MR{int(m[0])}.{int(m[1]):02d}" for m in mrs_sorted]
        log(f"Candidates: {candidates}")
        return candidates
        
    finally:
        driver.quit()


def get_latest_version() -> str:
    """Main detection logic."""
    # Check environment variable first
    env_ver = os.environ.get('LSA_VERSION', '').strip()
    if env_ver:
        log(f"Using LSA_VERSION: {env_ver}")
        if validate_version(env_ver):
            log("✓ Validated")
            return env_ver
        log("✗ Invalid, continuing auto-detection")
    
    log("=" * 70)
    log("LSA VERSION DETECTION")
    log("=" * 70)
    
    # Try Selenium
    result = scrape_versions()
    
    if result:
        versions = [result] if isinstance(result, str) else result
        log(f"\n✓ Found {len(versions)} candidate(s)")
        
        # Validate each
        for ver in versions:
            log(f"Validating {ver}...", end=' ')
            if validate_version(ver):
                log("✓")
                return ver
            log("✗")
    
    # Fallback
    log(f"\n⚠️  Using fallback: {FALLBACK_VERSION}")
    return FALLBACK_VERSION


def main():
    """Entry point."""
    try:
        version = get_latest_version()
        print(version, flush=True)
        return 0
    except Exception as e:
        log(f"ERROR: {e}")
        print(FALLBACK_VERSION, flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
