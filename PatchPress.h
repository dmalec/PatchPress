// --------------------------------------------------------------------------------
// Monitors one Pachube feed for changes, and calls back a registered function
// for each datastream entry.
//
// Adapted by Dan Malec from the Gutenbird sketch written by Adafruit Industries.
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
#ifndef PatchPress_h
#define PatchPress_h

#include <Arduino.h>
#include <Ethernet.h>

class PatchPress {

  public:
  PatchPress(EthernetClient *client, char *apiKey, char *feedId, unsigned long connectTimeout=15000L, unsigned long responseTimeout=15000L);

    void registerDatastreamEntryCallback(void (*datastreamEntryCallback)(char *, char *, double, double, double));
    void requestFeed();

  private:
    EthernetClient *client;

    // Configuration
    char *apiKey;
    char *feedId;
    unsigned long connectTimeout;
    unsigned long responseTimeout;

    // Callback To Process Entry Value
    void (*datastreamEntryCallback)(char *, char *, double, double, double);

    // Data Feed Data
    char lastTstamp[25];       // Time stamp in "ddd,DDMMMYYYYHH:MM:SSGMT" format

    // Data Stream Entry Data
    char readAt[28];           // Time stamp in "YYYY-MM-DDTHH:MM:SS.ssssssZ\0" format
    char dataStreamId[32];     // Data Stream ID
    double minValue;           // Minimum value
    double maxValue;           // Maximum value
    double curValue;           // Current value

    // JSON Parsing
    uint8_t datastreamsDepth;  // Depth of object parse
    char name[32];             // Temp space for name:value parsing
    char value[32];            // Temp space for name:value parsing


    boolean checkLastModifiedHeader();
    boolean jsonParse(int depth, byte endChar);
    boolean readString(char *dest, int maxLen);
    int unidecode(byte len);    
    int timedRead(void);
};

#endif
