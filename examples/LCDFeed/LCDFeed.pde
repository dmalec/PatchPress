// --------------------------------------------------------------------------------
// Monitors one Pachube datastream entry for changes, and calls back a registered
// function for each datastream entry.  The registered callback updates an LCD with
// the data and adjusts the backlight color based on the current value.
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
//
//
//      ******************************************************
//      Designed for the Adafruit RGB LCD Shield Kit
//      Pick one up at http://www.adafruit.com/products/716 !
//      ******************************************************
//
//
// --------------------------------------------------------------------------------
// Dependencies
// --------------------------------------------------------------------------------
// Adafruit Industries' RGB 16x2 LCD Shield library:
//       https://github.com/adafruit/Adafruit-RGB-LCD-Shield-Library
// Adafruit Industries' MCP23017 I2C Port Expander:
//       https://github.com/adafruit/Adafruit-MCP23017-Arduino-Library
// --------------------------------------------------------------------------------
#include <Ethernet.h>
#include <SoftwareSerial.h>
#include <SPI.h>
#include <Wire.h>

#include <Adafruit_MCP23017.h>
#include <Adafruit_RGBLCDShield.h>

#include "PatchPress.h"

// Networking
byte mac[] = { 0x90, 0xA2, 0xDA, 0x00, 0xE3, 0x8C };
IPAddress fallbackIpAddress(10,0,1,150);
EthernetClient client;

// Pachube config
//
// apiKey should be set to your Pachube API key
// feedId should be set to the feed you will be monitoring
// datastreamId should be set to the datastream ID you will be monitoring
// pollingInterval specifies milliseconds between polls of the Pachube server,
//                 which will limit you to 100/minute maximum
char *apiKey = "";
char *feedId = "23716";     // Boston air quality feed
char *datastreamId = "aqi"; // Air Quality Index datastream
const unsigned long pollingInterval = 60L * 1000L;
PatchPress patchPress(&client, apiKey, feedId);

// Display
Adafruit_RGBLCDShield lcd = Adafruit_RGBLCDShield();
#define RED 0x1
#define YELLOW 0x3
#define GREEN 0x2
#define TEAL 0x6
#define BLUE 0x4
#define VIOLET 0x5
#define WHITE 0x7

// Callback function to display current data on the LCD shield
void printEntryToLcd(char *dataStreamId, char *tstamp, double minValue, double maxValue, double curValue) {
  int i;

  // Set the backlight based on the current value.
  // In this case, the levels are set based on http://airnow.gov/ definitions of 
  // Good / Moderate / Other with anything higher than Moderate being red.
  if (curValue <= 50) {
    lcd.setBacklight(GREEN);
  } else if (curValue <= 100 ) {
    lcd.setBacklight(YELLOW);
  } else {
    lcd.setBacklight(RED);
  }

  // Slice the timestamp down to just month/day and hour:min:sec  
  // and display it on the first line.
  lcd.clear();
  lcd.setCursor(0, 0);
  for (i=5; i<=9; i++) {
    lcd.print(tstamp[i]);
  }
  lcd.setCursor(8, 0);
  for (i=11; i<=18; i++) {
    lcd.print(tstamp[i]);
  }

  // Show the Stream ID and the current value on the second line.
  lcd.setCursor(0, 1);
  lcd.print(dataStreamId);
  lcd.print(' ');
  lcd.print(curValue);
}

void setup() {
  Serial.begin(57600);

  // set up the LCD's number of rows and columns: 
  lcd.begin(16, 2);
  lcd.setBacklight(TEAL);
  
  // Register callback
  patchPress.setDatastream(datastreamId);
  patchPress.registerDatastreamEntryCallback(&printEntryToLcd);

  // Initialize Ethernet connection.  Request dynamic
  // IP address, fall back on fixed IP if that fails:
  lcd.setCursor(0, 0);
  lcd.print("Initializing....");
  
  Serial.print("Initializing Ethernet...");
  if(Ethernet.begin(mac)) {
    Serial.print("OK ");
  } else {
    Serial.print("\r\nno DHCP response, using static IP address.");
    Ethernet.begin(mac, fallbackIpAddress);
  }

  // Short delay so the IP can be spot checked.
  lcd.setCursor(0, 1);
  lcd.print(Ethernet.localIP());
  delay(3000);
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
