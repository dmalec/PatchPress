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
#include <SPI.h>
#include <Ethernet.h>
#include <SoftwareSerial.h>
#include "PatchPress.h"

// Networking
byte mac[] = { 0x90, 0xA2, 0xDA, 0x00, 0xE3, 0x05 };
IPAddress fallbackIpAddress(10,0,1,150);
EthernetClient client;

// Pachube config
char *apiKey = "";
char *feedId = "23716";
const unsigned long pollingInterval = 60L * 1000L; // Note: Pachube server will allow 100/min max
PatchPress patchPress(&client, apiKey, feedId);

void printEntryToSerial(char *dataStreamId, char *tstamp, double minValue, double maxValue, double curValue) {
  Serial.print("Data Stream Id: ");
  Serial.println(dataStreamId);
  Serial.print("Time: ");
  Serial.println(tstamp);
  Serial.print("Min: ");
  Serial.println(minValue);
  Serial.print("Max: ");
  Serial.println(maxValue);
  Serial.print("Cur: ");
  Serial.println(curValue);
}

void setup() {
  Serial.begin(57600);

  // Register callback
  patchPress.registerDatastreamEntryCallback(&printEntryToSerial);

  // Initialize Ethernet connection.  Request dynamic
  // IP address, fall back on fixed IP if that fails:
  Serial.print("Initializing Ethernet...");
  if(Ethernet.begin(mac)) {
    Serial.println("OK");
  } else {
    Serial.print("\r\nno DHCP response, using static IP address.");
    Ethernet.begin(mac, fallbackIpAddress);
  }
}

void loop() {
  unsigned long startTime = millis();
  unsigned long elapsedTime;

  patchPress.requestFeed();

  // Pause between queries, factoring in time already spent
  elapsedTime = millis() - startTime;
  if(elapsedTime < pollingInterval) {
    Serial.print("Pausing...");
    delay(pollingInterval - elapsedTime);
    Serial.println("done");
  }
}

