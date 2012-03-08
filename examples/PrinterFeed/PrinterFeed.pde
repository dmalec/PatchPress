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
//
//
//      ******************************************************
//      Designed for the Adafruit Internet of Things printer
//      Pick one up at http://www.adafruit.com/products/717 !
//      ******************************************************
//
//
// --------------------------------------------------------------------------------
#include <SPI.h>
#include <Ethernet.h>
#include <SoftwareSerial.h>
#include <Adafruit_Thermal.h>
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

// Printer config
const int printer_RX_Pin = 5;    // Printer connection: green wire
const int printer_TX_Pin = 6;    // Printer connection: yellow wire
const int printer_Ground = 7;    // Printer connection: black wire
Adafruit_Thermal printer(printer_RX_Pin, printer_TX_Pin);

// LED config
const int led_pin = 3;           // To status LED (hardware PWM pin)
byte sleepPos = 0;               // Current "sleep throb" table position
PROGMEM byte
  sleepTab[] = { // "Sleep throb" brightness table (reverse for second half)
      0,   0,   0,   0,   0,   0,   0,   0,   0,   1,
      1,   1,   2,   3,   4,   5,   6,   8,  10,  13,
     15,  19,  22,  26,  31,  36,  41,  47,  54,  61,
     68,  76,  84,  92, 101, 110, 120, 129, 139, 148,
    158, 167, 177, 186, 194, 203, 211, 218, 225, 232,
    237, 242, 246, 250, 252, 254, 255 };


void printEntryToPrinter(char *dataStreamId, char *tstamp, double minValue, double maxValue, double curValue) {
  int i;

  // Output to printer
  printer.wake();
  printer.inverseOn();
  printer.write(' ');
  printer.print(dataStreamId);
  for(i=strlen(dataStreamId); i<31; i++) printer.write(' ');
  printer.inverseOff();
  printer.underlineOn();
  printer.print(tstamp);
  for(i=strlen(tstamp); i<32; i++) printer.write(' ');
  printer.underlineOff();
  printer.print(curValue);
  printer.print(" (");
  printer.print(minValue);
  printer.print(" - ");
  printer.print(maxValue);
  printer.println(")");
  printer.feed(1);
  printer.sleep();
}

void setup() {
  // Set up LED "sleep throb" ASAP, using Timer1 interrupt:
  TCCR1A  = _BV(WGM11); // Mode 14 (fast PWM), 64:1 prescale, OC1A off
  TCCR1B  = _BV(WGM13) | _BV(WGM12) | _BV(CS11) | _BV(CS10);
  ICR1    = 8333;       // ~30 Hz between sleep throb updates
  TIMSK1 |= _BV(TOIE1); // Enable Timer1 interrupt
  sei();                // Enable global interrupts

  Serial.begin(57600);

  // Set up the printer
  pinMode(printer_Ground, OUTPUT);
  digitalWrite(printer_Ground, LOW);  // Just a reference ground, not power
  printer.begin();
  printer.sleep();

  // Register callback
  patchPress.registerDatastreamEntryCallback(&printEntryToPrinter);

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

  // Disable Timer1 interrupt during network access, else there's trouble.
  // Just show LED at steady 100% while working.  :T
  TIMSK1 &= ~_BV(TOIE1);
  analogWrite(led_pin, 255);

  patchPress.requestFeed();

  // Sometimes network access & printing occurrs so quickly, the steady-on
  // LED wouldn't even be apparent, instead resembling a discontinuity in
  // the otherwise smooth sleep throb.  Keep it on at least 4 seconds.
  elapsedTime = millis() - startTime;
  if(elapsedTime < 4000L) delay(4000L - elapsedTime);

  // Pause between queries, factoring in time already spent
  elapsedTime = millis() - startTime;
  if(elapsedTime < pollingInterval) {
    Serial.print("Pausing...");
    sleepPos = sizeof(sleepTab); // Resume following brightest position
    TIMSK1 |= _BV(TOIE1); // Re-enable Timer1 interrupt for sleep throb
    delay(pollingInterval - elapsedTime);
    Serial.println("done");
  }
}

// Timer1 interrupt handler for sleep throb
ISR(TIMER1_OVF_vect, ISR_NOBLOCK) {
  // Sine table contains only first half...reflect for second half...
  analogWrite(led_pin, pgm_read_byte(&sleepTab[
    (sleepPos >= sizeof(sleepTab)) ?
    ((sizeof(sleepTab) - 1) * 2 - sleepPos) : sleepPos]));
  if(++sleepPos >= ((sizeof(sleepTab) - 1) * 2)) sleepPos = 0; // Roll over
  TIFR1 |= TOV1; // Clear Timer1 interrupt flag
}
