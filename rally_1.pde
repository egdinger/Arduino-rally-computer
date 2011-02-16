#include <Wire.h>
#include <LiquidCrystal.h>
#include <EEPROM.h>
#include <EEPROM_UTIL.h>
#include <Keypad.h>
#include <SevenSegment.h>

#define MPH

//Update the version when nessacery
//The fourth char is the minor revision - change when cleaning up code / fixing a non-major bug
//The 3rd char is the major revision - change when fixing a major bug or every 25 minor bugs
//The 2nd char is the minor version - update when adding a small feature
//The 1st char is the major version - update with a major overhual.
//These really should only be update by one person, the branch owner, Eric Dinger. If you feel
//That your contribution should increment one of these and it's not reflected take it up with him.
const char VERSION[4] =  {'1','3','1','d'};

//used to let us know what data field we want to edit 
enum { i, f};

//This enum will define better names for menu pages
enum {odo, option, calibration, debug, raw};
//The following classes define the two types of odo's
//that will be used, countUp and countDown
//countUp will count up from 0
class countUp
{
  public:
  unsigned long startPulses;
  float calcDistance(unsigned long ulCount);
};

//countDown will be the same as countup
//With the addition of the startDistance field
//This will be used as a countdown timer.
class countDown: public countUp
{
  public:
  float startDistance;
  float calcDistanceLeft(unsigned long ulCount);
};

//Locations of the calibration values in EEPROM
const unsigned PPR_LOC = 0; //pulse per revolutions
const unsigned TIRE_SIZE_LOC = 4; //Tire size stored as a float packed into bytes
const unsigned LPULSECOUNT_LOC = 8; //ulPulseCount is stored here when the unit is turned off, packed into bytes.

//Locations of the data of the odo's this is so they can be persistant. That is exist across powercycles.
const unsigned ODO_TOT_START_PULSES_LOC = 12;
const unsigned ODO_1_START_PULSES_LOC = 16;
const unsigned ODO_DWN_START_PULSES_LOC = 20;
const unsigned ODO_DWN_START_DISTANCE_LOC = 24;
const unsigned UL_PULSE_COUNT_LOC = 28;

//Some conversion values used in the program
#ifdef MPH
  #define DISTANCE_CONVERSION_FACTOR 63360 //Inches in a mile
  #define PULSE_TIME_TO_SPEED 56818.1 //Conversion factor. Inches per uSec to MPH
#endif
#ifdef KPH
  #define DISTANCE_CONVERSION_FACTOR 1000 //m in a Km
  #define PULSE_TIME_TO_SPEED 91439.86 //Not sure if this correct, need to eval later.
#endif
const float pi = 3.14;
const byte MAX_DIGITS = 4;

//Pin values general
const byte PULSE = 3; //Needs to be on an interupt pin
const byte POWER = 99; //Needs to be on an interupt pin
//Pin values
const byte CLOCK_MODE_PIN = 99; //Need to set after next hardware revision.
//Pin values for LED display
const byte dataPin = 13; 
const byte clockPin = 4;
//Pin values for lcd
const byte SPI_CLK = 19;
const byte SPI_DATA = 18;
const byte LCD_CS = 17;
/* Disabled to test the i2c backpack. DINGER
const byte rs = 19; //A5
const byte en = 18; //A4
const byte d4 = 16; //A2
const byte d5 = 17; //A3
const byte d6 = 14; //A0
const byte d7 = 15; //A1
//Don't think I2C is going to work, too slow
//The following is a test list of pins using spi
//for the lcd and the rtc.
//CS for lcd
A0
//CS for RTC
A1
//SPI clk
A2
//mosi
A3
//miso
A4
//CLOCK select button
A5
*/
// pin values for matrix keypad
//These are named funny because thats what they are labeled on the keypad
//I'm using a greyhill 87BB3-201
const byte D = 9;
const byte E = 10;
const byte P = 11;
const byte Q = 12;
const byte M = 6;
const byte N = 5;
const byte G = 7;
const byte F = 8;


const byte ROWS = 4; //four rows
const byte COLS = 4; //three columns
char keys[ROWS][COLS] = {
  {'1','2','3','a'},
  {'4','5','6','b'},
  {'7','8','9','c'},
  {'#','0','*','d'}
};
byte rowPins[ROWS] = {D, E, P, Q}; //connect to the row pinouts of the keypad
byte colPins[COLS] = {M, N, G, F}; //connect to the column pinouts of the keypad

//The odometers available in the rally computer.
//Currently have 1 total distance, this will not be resetable by the reset button
//1 countup, this will be resetable from the reset button
//1 countdown, this will be resetable from the reset button, should this only count down when active?
countUp odoTotal;
countUp odo1;
countDown odo2;

//Various variables
volatile unsigned long ulPulseCount; //The total number of pulses that have occured since the last total reset. I have this as an
// unsigned becuase in this implementation it is an error if ulPulseCount goes negative.
byte bPpr; //The number of pulses per revolution. Since I'm basing this off a sensor that reads the number of lug studs
//This is very unlikely to be greater than 8. But since it may be used with the vehicles existing vss it could be higher.
//64 would not be unlikely when used in this way.
float fDistancePerPulse; //This will be a calculated value.
float fTire; //Tire diameter, read from the eeprom
float fCirc; //calc'ed
float fTemp; //used as a temp accumulator
byte bTemp; //used as a temp accumlator
volatile unsigned long ulOldMicros;
volatile unsigned long uiPulseInt;
volatile unsigned long ulTempPulseCount;

//These are state variables. Together they contain the state of the menu's and displays.
byte bCurrentOdo; //Which is the current odo we have selected
byte bPage; //Which is the current lcd data page we want to display
byte bEditMode; //Used to indicate if we want to edit data on the lcd screen
byte bEditSelection; //Used to indicate what we want to edit, if there is more than 1 editable field on the page


byte bCurSpeed; //I've alrealy forgotten what this was for. It looks like I'm not using it anywhere, investigate the impact of removing it


//LiquidCrystal lcd(rs, en, d4, d5, d6, d7);
LiquidCrystal lcd(SPI_DATA, SPI_CLK, LCD_CS);
Keypad keypad = Keypad( makeKeymap(keys), rowPins, colPins, ROWS, COLS );
SevenSegment led = SevenSegment(dataPin, clockPin, MAX_DIGITS);

//Function definitions, look below for more extensive documentation
void pulseHandler();
void calDisplay();
void saveCalibration();
void updateLED(int odo);
void updateLCD();
int calcCurrentSpeed(long pt);
void buttonHandler(char key);
void shutdownHandler();
void getPersitantData();
void calcTireDetails();

void setup()
{  
  pinMode(PULSE, INPUT);
  digitalWrite(PULSE, HIGH);
  //uncomment when I have the clock and button implmented
  //pinMode(CLOCK_MODE_PIN, INPUT);
  //digitalWrite(CLOCK_MODE_PIN, HIGH);
  Serial.begin(9600);
  
  bCurrentOdo = 1; //Default odo
  bPage = 0;
  fTemp = .00;
  bTemp = 0;
  getPersitantData();
  ulOldMicros = micros();
  
  calcTireDetails();
  
  digitalWrite(D, HIGH);
  digitalWrite(E, HIGH);
  digitalWrite(P, HIGH);
  digitalWrite(Q, HIGH);
  
  lcd.begin(20,4);
  calDisplay();
  led.displayChars(VERSION);
  delay(2000); //Wait two seconds so the user can see the configuration data on the lcd screen
  lcd.clear();
  
  //Attach the interupt handlers. We do this last so no interupts occur while we are setting up the system.
  attachInterrupt(1, pulseHandler, FALLING);
  //attachInterupt(0, shutdownHandler, FALLING); Which pin?
}
//Temp for testing
unsigned long ulLcdPreviousTime = 0;
unsigned long ulLedPreviousTime = 0;
unsigned long ulCurrTime;
boolean bLedIsClock = false;
void loop()
{
  char key;
  ulCurrTime = millis();
  //Not yet implemented
  
  //check buttons
  key = keypad.getKey();
  
  if ((ulCurrTime - ulLcdPreviousTime) >= 100) //Limit the refresh rate of the lcd
  {
    cli();
    ulTempPulseCount = ulPulseCount;
    sei();
    //update the LCD
    updateLCD();
    ulLcdPreviousTime = ulCurrTime;
  }
  if((ulCurrTime - ulLedPreviousTime) >= 100) //Limit th refresh rate of the led
    {
      //Check if we want to display the clock
      if (bLedIsClock)
      {
        Serial.println("clock");
         //Get time from where ever
         //Display time on the LED
         led.displayChars("cloc");
      }
      else
      {
        updateLED(bCurrentOdo);
      }
      ulLedPreviousTime = ulCurrTime;
    }  
  
  if (key != NO_KEY){
    buttonHandler(key);
  }

  //get current speed
  //Serial.print(calcCurrentSpeed(uiPulseInt));
  delay(50);
}

//Displays the values of the calibration data
//Displays over serial and on the LCD
void calDisplay()
{
  //Doing this with serial and lcd
  Serial.print("Tire Diameter: ");
  Serial.println(fTire);
  Serial.print("PPR: ");
  Serial.println(bPpr, DEC);
  lcd.setCursor(0,0);
  lcd.print("Tire Dia: ");
  lcd.print(fTire);
  lcd.setCursor(0,1);
  lcd.print("PPR: ");
  lcd.print(bPpr, DEC);
  lcd.setCursor(0,2);
  lcd.print(VERSION);
}

//
void pulseHandler()
{
  unsigned long ulCurrentMicros;
  //ADD DINGER get the time here so we don't have to use pulseIn
  ulCurrentMicros = micros();
  uiPulseInt = ulCurrentMicros - ulOldMicros;
  ulOldMicros = ulCurrentMicros;
  ulPulseCount++;
}

//Resets the current odo
void resetCurrentOdo()
{
  switch (bCurrentOdo)
  {
    case 0:
      //Not resetable here - this is the total odo. Can only be reset with a master reset.
      break;
    case 1: //ODO1
      cli();
      odo1.startPulses = ulPulseCount;
      sei();
      break;
    case 2: //odo 2
      cli();
      odo2.startPulses = ulPulseCount;
      sei();
      break;
    default:
      //Undefined/shouldn't have got here. So do nothing.
      lcd.clear();
      lcd.print("Error 8");
      break;
  }
}

//Resets all of the odo's and the current pulse count.
//Once this has been done it cannot be undone.
void masterReset()
{
  cli();
  ulPulseCount = 0;
  sei();
  odo1.startPulses = ulPulseCount;
  odo2.startPulses = ulPulseCount;
  odoTotal.startPulses = ulPulseCount;
  lcd.clear();
  lcd.print("Master reset");
  delay(2000);
  lcd.clear();
}

//This function performs the calculations on the data and
//writes it out to the LED display
void updateLED(int odo)
{
  switch (odo)
  {
    case 0:
      //distance, decimal place at 2 digits in, leading zero suppresed.
      led.displayNum(odoTotal.calcDistance(ulTempPulseCount), 2, 1);
      break;
    case 1:
      //Count up
      led.displayNum(odo1.calcDistance(ulTempPulseCount), 2, 1);
      break;
    case 2:
      //Count down
      led.displayNum(odo2.calcDistanceLeft(ulTempPulseCount), 2, 1);
      break;
    default:
      //Shouldn't have got here display error code.
      lcd.clear();
      lcd.print("Error 9");
      break;
  }
}

//Prints less important data to the lcd
void updateLCD()
{
  //cli();
  //unsigned long ulTempCount = ulPulseCount;
  //sei();
  
  //Using a 20x4 lcd will look something like
  //Page 0
  //ODO TOT: xxx.xx
  //ODO   1: xx.xx
  //ODO DWN: xx.xx
  //XXX
  //Page 1
  //Unsure
  //Page 2
  //1: Configuration
  //2: Master Reset
  //3: Shutdown
  //4: raw odo values - for testing purposes.
  switch(bPage)
  {
    case odo:
      //The first page will display all of the available odo's and some information about them
      //Not sure if I want to display the count or what we want to count down from for count down
      lcd.setCursor(0,0);
      lcd.print("ODO TOT:");
      lcd.setCursor(9,0);
      lcd.print(odoTotal.calcDistance(ulTempPulseCount));
      lcd.setCursor(0,1);
      lcd.print("ODO   1:");
      lcd.setCursor(9,1);
      lcd.print(odo1.calcDistance(ulTempPulseCount));
      lcd.setCursor(0,2);
      lcd.print("ODO DWN:");
      if (bEditMode)
      {
        lcd.setCursor(8,2);
        lcd.print("^");
        lcd.print(fTemp);
      }
      else
      {
        lcd.setCursor(9,2);
        //Do I want to count down here, or only on the led?
        //        lcd.print(odo2.startDistance);
        lcd.print(odo2.calcDistanceLeft(ulTempPulseCount));
      }
      lcd.setCursor(13, bCurrentOdo);
      lcd.print("@");
      break;
    case debug:
      lcd.setCursor(0,0);
      lcd.print("Debug Stuff:");
      lcd.setCursor(0,1);
      lcd.print(ulPulseCount);
      lcd.setCursor(0,2);
      lcd.print("Selected ODO:");
      lcd.setCursor(14,2);
      lcd.print(bCurrentOdo, DEC);
      break;
    case option:
      lcd.setCursor(1,0);
      lcd.print("1: Configuration");
      lcd.setCursor(1,1);
      lcd.print("2: Master Reset");
      lcd.setCursor(1,2);
      lcd.print("3: Shutdown");
      if (bEditMode)
      {
        lcd.setCursor(0,1);
        lcd.print("^");
      }
      break;
    case calibration:
      //The calibration menu
      lcd.setCursor(0,0);
      lcd.print("Pulses per rev:");
      lcd.setCursor(15,0);
      if(bEditSelection == i && bEditMode)
      {
        lcd.print("^");
        lcd.print(bTemp, DEC);
      }
      else
      {
        lcd.print(bPpr, DEC);
      }
      
      lcd.setCursor(0,1);
      lcd.print("Tire diameter:");
      lcd.setCursor(14,1);
      if(bEditSelection == f && bEditMode)
      {
        lcd.print("^");
        lcd.print(fTemp);
      }
      else
      {
        lcd.print(fTire);
      }
      break;
    case raw:
      // This will display the first and last value that gets saved in the shutdown handler
      // This is done so we can compare that they saved correctly.
      lcd.setCursor(0,0);
      lcd.print(ulPulseCount);
      lcd.setCursor(0,1);
      lcd.print(odo2.startDistance);
      break;
    default:
      lcd.clear();
      lcd.print("Error 10");
      break;    
  }
  //Do I want to display the current speed here all the time?
  lcd.setCursor(0,3);
  lcd.print(calcCurrentSpeed(uiPulseInt), DEC);
  lcd.print("   ");
}

//Calculates the current speed with pulse time given in microseconds
//returns speed in mph
int calcCurrentSpeed(long pt)
{  
  return ((fDistancePerPulse/pt)*PULSE_TIME_TO_SPEED);
}

//Uses prompts to get data from the user and then
//saves it to eeprom using the locations defined at the begining of the file.
void saveCalibration()
{
  EEPROM.write(PPR_LOC, bPpr);
  EEPROM_writeAnything(TIRE_SIZE_LOC, fTire);
  calcTireDetails();
  lcd.clear();
  lcd.print("Calibration saved");
  delay(1000);
  lcd.clear();
}

void buttonHandler(char key)
{
  switch (key)
  {
    case '1':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .01; 
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 1;   
        }
      }
      if(bPage == option && bEditMode == true)
      {
        bPage = calibration;
        bEditMode = !bEditMode;
        lcd.clear();
      }
      break;
    case '2':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .02;
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 2;
        }
      }
      if(bPage == option && bEditMode == true)
      {
        masterReset();
        bEditMode = false;//!bEditMode;
      }
      break;
    case '3':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .03;
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 3;
        }
      }
      if(bPage == option && bEditMode == true)
      {
        shutdownHandler();
        bEditMode = false;//!bEditMode;
      }
      break;
    case '4':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .04;
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 4;
        }
      }
      break;
    case '5':
      if(!bEditMode)
      {
        bLedIsClock = !bLedIsClock;
      }
      else //We're in edit mode
      {
        if(bPage == odo || bPage == calibration)
        {
          if(bEditSelection == f)
          {
            fTemp = fTemp * 10 + .05;
          }
          if(bEditSelection == i)
          {
            bTemp = bTemp * 10 + 5;
          }
        }
      }
      break;
    case '6':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .06;
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 6;
        }
      }
      break;
    case '7':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .07;
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 7;
        }
      }
      break;
    case '8':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .08;
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 8;
        }
      }
      break;
    case '9':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .09;
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 9;
        }
      }
      break;
    case '0':
      if(bPage == odo || bPage == calibration && bEditMode == true)
      {
        if(bEditSelection == f)
        {
          fTemp = fTemp * 10 + .00;
        }
        if(bEditSelection == i)
        {
          bTemp = bTemp * 10 + 0;
        }
      }
      break;
    case 'a':
      //if we are in edit mode
      if(bEditMode)
      {
        if(bPage == 3)
        {
          bEditSelection = bEditSelection == i ? f : i;
          lcd.clear();
        }
      }
      else //Can't change pages when you are editing
      {
        //The following line sets the total number of pages we can cycle through.
        bPage = (bPage + 1) % 5;
        lcd.clear();
      }
      break;
    case 'b':
      //swap the current/active odometer
      //This means the one displayed on the LED display also the one affected by reset
      bCurrentOdo = (++bCurrentOdo % 3);
      lcd.clear();
      break;
    case 'c':
      if(bPage == 3 && !bEditMode)
      {
        saveCalibration();
        bEditMode = !bEditMode;
        bEditSelection = f;
      }
      break;
    case 'd':
      resetCurrentOdo();
      break;
    case '#':
      //enter edit mode

      if(bPage == 0 && bEditMode)
      {
        odo2.startDistance = fTemp;
      }
      if(bPage == 3 && bEditMode)
      {
        if(bEditSelection == i)
        {
          bPpr = bTemp;
        }
        if(bEditSelection == f)
        {
          fTire = fTemp;
        }
      }
      bTemp = 0;
      fTemp = 0;
      bEditMode = !bEditMode;
      //This assumes that any page with an edit field has a float edit field.
      //May need to update if this no longer is true.
      bEditSelection = f;
      lcd.clear();
      break;
    case '*':
      //Commit change
      if(bEditMode)
      {
         //We are in edit mode so clear any unsaved value
         fTemp = 0;
         bTemp = 0;
         //exit edit mode
         bEditMode = !bEditMode;
         lcd.clear();
      }
      break;
      default:
        lcd.println("Invalid input character. Internal error");
        Serial.print("Invalid input character: ");
        Serial.println(key);
        Serial.print("Please take to service!");
      }
}

//This function should be called before we loose power to save the state of
//the odo's so they can be recalled
void shutdownHandler()
{
  //Save the current ulPulseCount and odo statuses
  
  //IF THE ORDER IS CHANGED MAKE SURE TO UPDATE PAGE 4!!!
  //PAGE 4 is raw.
  EEPROM_writeAnything(UL_PULSE_COUNT_LOC, ulPulseCount);
  EEPROM_writeAnything(ODO_TOT_START_PULSES_LOC, odoTotal.startPulses);
  EEPROM_writeAnything(ODO_1_START_PULSES_LOC, odo1.startPulses);
  EEPROM_writeAnything(ODO_DWN_START_PULSES_LOC, odo2.startPulses);
  EEPROM_writeAnything(ODO_DWN_START_DISTANCE_LOC, odo2.startDistance);
  
  //This is temporary untill I figure out more about the power supply, ie can I shut it off remotely, etc
  lcd.clear();
  lcd.print("Safe to shutdown");
  while(true);
}

//This function will be called when the device first starts and
//after we update any of the configurable persistant data
void getPersitantData()
{
  bPpr = EEPROM.read(PPR_LOC); //Get the stored value for ppr
  EEPROM_readAnything(TIRE_SIZE_LOC, fTire); //Get the stored value for the tire size
  EEPROM_readAnything(UL_PULSE_COUNT_LOC, ulPulseCount);
  EEPROM_readAnything(ODO_TOT_START_PULSES_LOC, odoTotal.startPulses);
  EEPROM_readAnything(ODO_1_START_PULSES_LOC, odo1.startPulses);
  EEPROM_readAnything(ODO_DWN_START_PULSES_LOC, odo2.startPulses);
  EEPROM_readAnything(ODO_DWN_START_DISTANCE_LOC, odo2.startDistance);
}

void calcTireDetails()
{
  //Calculate the tire circumfrance and the distance per pulse
  fCirc = fTire * pi;
  fDistancePerPulse = fCirc/bPpr;
};

//Calculates the distance traveled.
float  inline countUp::calcDistance(unsigned long ulCount)
{
  //Investigate computing fDistancePerPulse / DISTANCE_CONVERSION_FACTOR into a 
  //single varible to reduce the number of floating point calculations we have to 
  //everytime we update the lcd/led screen.
  return (ulCount - startPulses) * fDistancePerPulse / DISTANCE_CONVERSION_FACTOR;
}

//Calculates the distance remaining till we have traveled the distance held in startDistance
float  inline countDown::calcDistanceLeft(unsigned long ulCount)
{
  return startDistance - ((ulCount - startPulses) * fDistancePerPulse / DISTANCE_CONVERSION_FACTOR);
}
