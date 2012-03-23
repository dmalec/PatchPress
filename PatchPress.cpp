// --------------------------------------------------------------------------------
// Monitors one Pachube feed for changes, and calls back a registered function
// for each datastream entry.
//
// Adapted by Dan Malec from the Gutenbird sketch written by Adafruit Industries.
//   Original Gutenbird sketch https://github.com/adafruit/Adafruit-Tweet-Receipt
//
// MIT license.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// --------------------------------------------------------------------------------
#include "PatchPress.h"

//! Class constructor.
/*!
  The class constructor saves the configuration parameters.
  
  \param client a pointer to the Ethernet client object
  \param apiKey the string developer API key
  \param feedId the string feed ID
  \param connectTimeout the amount of time to wait when connecting to pachube before timing out
  \param responseTimeout the amount of time to wait for a response from pachube before timing out
 */
PatchPress::PatchPress(EthernetClient *client, char *apiKey, char *feedId, unsigned long connectTimeout, unsigned long responseTimeout) {
  this->client = client;
  this->apiKey = apiKey;
  this->feedId = feedId;
  this->datastreamId = NULL;
  this->connectTimeout = connectTimeout;
  this->responseTimeout = responseTimeout;

  datastreamEntryCallback = NULL;
  isDataObjectRoot = false;

  memset(lastTstamp, '\0', sizeof(lastTstamp));
  memset(readAt, '\0', sizeof(readAt));
  memset(dataStreamId, '\0', sizeof(dataStreamId));
  memset(name, '\0', sizeof(name));
  memset(value, '\0', sizeof(value));
}

//! Register a callback for when the parser sees a datastream entry.
/*!
  Pass in a function pointer to be called when the end of a datastream entry is reached in the JSON feed.

  \param datastreamEntryCallback the function pointer of the callback
*/
void PatchPress::registerDatastreamEntryCallback(void (*datastreamEntryCallback)(char *, char *, double, double, double)) {
  this->datastreamEntryCallback = datastreamEntryCallback;
}

//! Set a datastream ID to filter down to from the overall feed.
/*!
  \param datastreamId the string datastream ID to filter by in addition to the feed ID
*/
void PatchPress::setDatastream(char *datastreamId) {
  this->datastreamId = datastreamId;
  if (datastreamId != NULL) {
    isDataObjectRoot = true;
  }
}

//! Request data from pachube.
/*!
  Request either the feed JSON or the datastream JSON and callback the registered function pointer
  on the returned data.  If the data has not changed since the last poll, do nothing.
 */
void PatchPress::requestFeed() {
  unsigned long startTime;
  boolean updated;

  // Attempt server connection, with timeout...
  Serial.print("Connecting to server...");
  startTime = millis();
  while((client->connect("api.pachube.com", 80) == false) &&
    ((millis() - startTime) < connectTimeout));

  if(client->connected()) { // Success!
    Serial.print("OK\r\nIssuing HTTP request...");

    client->print("GET /v2/feeds/");
    client->print(feedId);
    if (datastreamId != NULL) {
      client->print("/datastreams/");
      client->print(datastreamId);
    }
    client->print(".json");
    client->print(" HTTP/1.1\r\nHost: api.pachube.com");
    client->print("\r\nX-PachubeApiKey: ");
    client->print(apiKey);
    client->println("\r\nConnection: close\r\n");

    Serial.print("OK\r\nAwaiting results (if any)...");
    startTime = millis();
    while((!client->available()) && ((millis() - startTime) < responseTimeout));
    if(client->available()) { // Response received?
      updated = checkLastModifiedHeader();
      if (!updated) {
        Serial.print("Not updated since last read ");
        Serial.println(lastTstamp);
      } else if(client->find("\r\n\r\n")) { // Skip other HTTP response headers
        Serial.println("OK\r\nProcessing results...");
        datastreamsDepth = 0;
        jsonParse(0, 0);
      } else {
        Serial.println("response not recognized.");
      }
    } else {
      Serial.println("connection timed out.");
    }
    client->stop();
  } else { // Couldn't contact server
    Serial.println("failed");
  }
}

//! Check the header fields in the HTTP response to see if the data is modified since the last read.
/*!
  If a feed is being requested, check the Last-Modified header.  If a datastream entry is being requested,
  check the ETag header.
 */
boolean PatchPress::checkLastModifiedHeader() {
  boolean parsing = true;
  boolean foundHeader = false;
  int i = 0, c;
  char tstamp[40]; // ddd,DDMMMYYYYHH:MM:SSGMT or 32 character etag

  memset(tstamp, 0, sizeof(tstamp));

  if (datastreamId == NULL) {
    foundHeader = client->findUntil("Last-Modified:", "\r\n\r\n");
  } else {
    foundHeader = client->findUntil("ETag:", "\r\n\r\n");
  }

  if (foundHeader) {
    while (parsing && client->available()) {
      c = client->peek();
      if (c == '\r' || i >= 38) {
        tstamp[i] = '\0';
        parsing = false;
      } else if (!isspace(c)) {
        tstamp[i++] = (char)client->read();
      } else {
        client->read(); // skip whitespace
      }
    }
  }
  
  if (!strncasecmp(tstamp, lastTstamp, sizeof(lastTstamp))) {
    return false;
  } else {
    strncpy(lastTstamp, tstamp, sizeof(lastTstamp)-1);
    return true;
  }
}

boolean PatchPress::jsonParse(int depth, byte endChar) {
  int c;
  boolean readName = true;

  for(;;) {
    while(isspace(c = timedRead())); // Scan past whitespace
    if(c < 0)        return false;   // Timeout
    if(c == endChar) return true;    // EOD

    if(c == '{') { // Object follows
      if(!jsonParse(depth + 1, '}')) return false;
      if(!depth && !isDataObjectRoot) return true; // End of file
      if(depth == datastreamsDepth) { // End of object in results list

	// Notify callback of entry data
        if (datastreamEntryCallback != NULL) {
          (*datastreamEntryCallback)(dataStreamId, readAt, minValue, maxValue, curValue);
        }
       
        // Clear values
        memset(readAt, '\0', sizeof(readAt));
        memset(dataStreamId, '\0', sizeof(dataStreamId));
        minValue = maxValue = curValue = 0.0;
      }
      if(!depth && isDataObjectRoot) return true; // End of file
    } else if(c == '[') { // Array follows
      if((!datastreamsDepth) && (!strcasecmp(name, "datastreams")))
        datastreamsDepth = depth + 1;
      if(!jsonParse(depth + 1,']')) return false;
    } else if(c == '"') { // String follows
      if(readName) { // Name-reading mode
        if(!readString(name, sizeof(name)-1)) return false;
      } else { // Value-reading mode
        if(!readString(value, sizeof(value)-1)) return false;
        // Process name and value strings:
        if       (!strcasecmp(name, "id")) {
          strncpy(dataStreamId, value, sizeof(dataStreamId)-1);
        } else if(!strcasecmp(name, "at")) {
          strncpy(readAt, value, sizeof(readAt)-1);
        } else if(!strcasecmp(name, "min_value")) {
          minValue = atof(value);
        } else if(!strcasecmp(name, "max_value")) {
          maxValue = atof(value);
        } else if(!strcasecmp(name, "current_value")) {
          curValue = atof(value);
        }
      }
    } else if(c == ':') { // Separator between name:value
      readName = false; // Now in value-reading mode
      value[0] = 0;     // Clear existing value data
    } else if(c == ',') {
      // Separator between name:value pairs.
      readName = true; // Now in name-reading mode
      name[0]  = 0;    // Clear existing name data
    } // Else true/false/null or a number follows.  These values aren't
      // used or expected by this program, so just ignore...either a comma
      // or endChar will come along eventually, these are handled above.
  }
}

// ---------------------------------------------------------------------------

// Read string from client stream into destination buffer, up to a maximum
// requested length.  Buffer should be at least 1 byte larger than this to
// accommodate NUL terminator.  Opening quote is assumed already read,
// closing quote will be discarded, and stream will be positioned
// immediately following the closing quote (regardless whether max length
// is reached -- excess chars are discarded).  Returns true on success
// (including zero-length string), false on timeout/read error.
boolean PatchPress::readString(char *dest, int maxLen) {
  int c, len = 0;

  while((c = timedRead()) != '\"') { // Read until closing quote
    if(c == '\\') {    // Escaped char follows
      c = timedRead(); // Read it
      // Certain escaped values are for cursor control --
      // there might be more suitable printer codes for each.
      if     (c == 'b') c = '\b'; // Backspace
      else if(c == 'f') c = '\f'; // Form feed
      else if(c == 'n') c = '\n'; // Newline
      else if(c == 'r') c = '\r'; // Carriage return
      else if(c == 't') c = '\t'; // Tab
      else if(c == 'u') c = unidecode(4);
      else if(c == 'U') c = unidecode(8);
      // else c is unaltered -- an escaped char such as \ or "
    } // else c is a normal unescaped char

    if(c < 0) return false; // Timeout

    // In order to properly position the client stream at the end of
    // the string, characters are read to the end quote, even if the max
    // string length is reached...the extra chars are simply discarded.
    if(len < maxLen) dest[len++] = c;
  }

  dest[len] = 0;
  return true; // Success (even if empty string)
}

// ---------------------------------------------------------------------------

// Read a given number of hexadecimal characters from client stream,
// representing a Unicode symbol.  Return -1 on error, else return nearest
// equivalent glyph in printer's charset.  (See notes below -- for now,
// always returns '-' or -1.)
int PatchPress::unidecode(byte len) {
  int c, v, result = 0;
  while(len--) {
    if((c = timedRead()) < 0) return -1; // Stream timeout
    if     ((c >= '0') && (c <= '9')) v =      c - '0';
    else if((c >= 'A') && (c <= 'F')) v = 10 + c - 'A';
    else if((c >= 'a') && (c <= 'f')) v = 10 + c - 'a';
    else return '-'; // garbage
    result = (result << 4) | v;
  }

  // To do: some Unicode symbols may have equivalents in the printer's
  // native character set.  Remap any such result values to corresponding
  // printer codes.  Until then, all Unicode symbols are returned as '-'.
  // (This function still serves an interim purpose in skipping a given
  // number of hex chars while watching for timeouts or malformed input.)

  return '-';
}

// Read from client stream with a 5 second timeout.  Although an
// essentially identical method already exists in the Stream() class,
// it's declared private there...so this is a local copy.
int PatchPress::timedRead(void) {
  int           c;
  unsigned long start = millis();

  while((!client->available()) && ((millis() - start) < 5000L));

  c = client->read();  // -1 on timeout
  return c;
}
