/*
  SevenSegment.h - A library for displaying numbers on a bank of 7-segment displays
                   connected to a bank of shift registers
  Original author: Jeff Kravitz
  
  Project: Arduino Rally Computer
  Modifications by: Eric Dinger
  
  This version has been modified from Jeff Kravitz original version to be used in
  a pin limited enviroment. The version uses only 2 pins, but loses control over
  the brightness of the display, the ability to fade in/out and enable/disable the
  display. It is still possible to blank the display using the blank characters.

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with this library; if not, write to the Free Software
  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*/

#ifndef SevenSegment_h
#define SevenSegment_h

#define NDIGITS 8

#include <WProgram.h>
#include <avr/pgmspace.h>

/*
 * Segments to be switched on for digits and punctuation on
 * 7-Segment Displays
 */
static byte DigitSegments[10] PROGMEM = {
      0xfc,0x60,0xda,0xf2,0x66,0xb6,0xbe,0xe0,0xfe,0xf6
};

const static byte MinusSegments = 0x02;
const static byte DecPoint      = 0x01;

class SevenSegment {
 private :
    /* The array for shifting the data to the devices */
    byte digits[NDIGITS];
    /* Data is shifted out of this pin */
    byte data_pin;
    /* The clock is signaled on this pin */
    byte clock_pin;
    /* This one is driven HIGH for chip selection */
    byte enable_pin;
    /* Number of 7 segment digit displays */
    int maxdigits;
    /* The number of digits to the right of the decimal point */
    int decimal_digits;
    /* boolean indicating if leading zeros are suppressed */
    boolean zerosup;
    /* boolean indicating negative number */
    boolean negative;
    
    boolean debugFlag;
    
    void calcValue(long v, int intDigits, int digitIndex);
	void segOutput(byte *segments);
    int  numDigits(double n);
    byte getChar(unsigned char data);
    long Pow10(int p);
 public:
    /* 
     * Create a new SevenSegment object 
     * Params :
     * dataPin		pin on the Arduino where data gets shifted out
     * clockPin		pin for the clock
     * enablePin	pin for selecting the device 
     * maxDigits    number of 7 segment displays
     */
    //SevenSegment(int dataPin, int clkPin, int enablePin, int maxDigits);
	
	/*
	 * A version that doesn't use the enable pin
	 */
	SevenSegment(int dataPin, int clkPin, int maxDigits);
    
    /* 
     * Switch all segments on the display off. 
     */
    void clearDisplay();

    /* 
     * Display a floating point (double) number with optional decimal places
     * 
     * Params:
     * value	  double - floating point number between -XXX and XXXX 
     * dp		  int - number of digits to the right of the decimal point
     * lzsuppress boolean - true if leading zeros should be displayed as blanks
     *
     * Returns:
     *   0 if successful
     *  -1 if error detected (number too large for display)
     */
    int displayNum(double value, int dp, boolean lzsuppress);
    
    /* 
     * Display a set of digits or blanks 0-9 = digit, 10 = blank
     */
    void displayDigits(int theDigits[]);
    
    /* 
     * Display a set of ASCII characters
     */
    void displayChars(const char theChars[]);
    
    void debug();
};

#endif	//SevenSegment.h



