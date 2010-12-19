/*
  SevenSegment.cpp - A library for displaying numbers on a bank of 7-segment displays
                     connected to a bank of shift registers
  Copyright (c) 2009 Jeff Kravitz


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

#include "SevenSegment.h"
#include <math.h>
	
SevenSegment::SevenSegment(int dataPin, int clkPin, int maxDigits) {
    data_pin = dataPin;
    clock_pin = clkPin;
    maxdigits = maxDigits;
    if (maxdigits > NDIGITS) maxdigits = NDIGITS;
    debugFlag = 0;
    pinMode(data_pin,OUTPUT);
    pinMode(clock_pin,OUTPUT);
    digitalWrite(clock_pin,LOW);
    clearDisplay();
    }


void SevenSegment::clearDisplay() {
    for (int i = 0; i < (maxdigits * 8); ++i) shiftOut(data_pin,clock_pin,LSBFIRST,0x00);
}

int SevenSegment::displayNum(double value, int dp, boolean lzsuppress) {
    byte segments[NDIGITS];
    long integerValue;
    long fractionValue;
    double iValue;
    double fValue;
    int  digitIndex = 0;
    int  intDigits = maxdigits;
    
    if (dp > maxdigits) return -1;
    if (value < 0.0) negative = 1;
    else             negative = 0;
    if (negative) value = -value;
    fValue = modf(value,&iValue);
	fValue += .005; //This is added so that the truncation on line 59 will behave like
	//the rounding in the lcd and serial libraries.
    integerValue = (long) iValue;
    fractionValue = (long) (fValue * Pow10(dp));
    if (negative) {
       --intDigits;
       ++digitIndex;
       }
    intDigits -= dp;
    // check here for overflow
    if (numDigits(value) > intDigits) {
       return -1;
	   //FIX DINGER
	   //Add some logic to remove the digits greater than we can display 
	   //And display only the digits that we can.
       }
    calcValue(integerValue,intDigits,digitIndex);
    if (dp != 0) {
       calcValue(fractionValue,dp,digitIndex+intDigits);
       }
    digitIndex = 0;
    intDigits = maxdigits;
    if (negative) {
        segments[0] = MinusSegments;
        ++digitIndex;
    }
    for (int i = digitIndex; i < maxdigits; ++i) {
       segments[i] = pgm_read_byte (& DigitSegments[digits[i]]);
       }
    if (lzsuppress) {
       for (int i = digitIndex; i < maxdigits; ++i) {
           if (digits[i] != 0) break;
           if (dp > 0 && i <= ((maxdigits-1)-dp)) {
              segments[i] = 0x00;
              }
           }
        }    
    if (dp != 0) segments[(maxdigits-1)-dp] |= DecPoint;
    segOutput(segments);  
    return 0;
}
    
void SevenSegment::calcValue(long v, int intDigits, int digitIndex) {  

    for (int i = 0; i < intDigits; ++i) {
       long powOfTen = Pow10((intDigits-i)-1);
       if (i == (intDigits-1)) digits[digitIndex+i] = v;
       else digits[digitIndex+i] = (v / powOfTen);
       v = v % powOfTen;
    }
}    
       
void SevenSegment::segOutput(byte *segments) {
    for (int i = maxdigits-1; i >= 0; --i) {
       shiftOut(data_pin,clock_pin,LSBFIRST,segments[i]);
       }
}

void SevenSegment::displayDigits(int theDigits[]) {
    byte segments[NDIGITS];

    for (int i = 0; i < maxdigits; ++i) {
       if (theDigits[i] == 10) segments[i] = 0x00;
       else                    segments[i] = pgm_read_byte(&DigitSegments[theDigits[i]]);
       }
    segOutput(segments);   
}    
 
void SevenSegment::displayChars(byte theChars[]) {
    byte segments[NDIGITS];

    for (int i = 0; i < maxdigits; ++i) {
       segments[i] = getChar(theChars[i]);
       }
    segOutput(segments);   
}
 
   
void SevenSegment::debug() {
   byte seg;
   debugFlag = 1;
   for (int i = 0; i < 10; ++i) {
      seg = pgm_read_byte(&DigitSegments[i]);
      shiftOut(data_pin,clock_pin,LSBFIRST,seg);
      shiftOut(data_pin,clock_pin,LSBFIRST,seg);
      shiftOut(data_pin,clock_pin,LSBFIRST,seg);
      shiftOut(data_pin,clock_pin,LSBFIRST,seg);
      delay(250);
    }
}

int SevenSegment::numDigits(double n) {
   if (n == 0.0) return 1;
   return int((floor ( log10 ( n ) )) + 1); 
   }

byte SevenSegment::getChar(unsigned char data) {
   switch (data) {
  case '0':
    return 0xfc;
  case '1':
    return 0x60;
  case '2':
    return 0xda;
  case '3':
    return 0xf2;
  case '4':
    return 0x66;
  case '5':
    return 0xb6;
  case '6':
    return 0xbe;
  case '7':
    return 0xe0;
  case '8':
    return 0xfe;
  case '9':
    return 0xf6;
  case 'A':
    return 0xee;
  case 'a':
    return 0xfa;
  case 'B':
    return 0x3e;  //
  case 'b':
    return 0x3e;
  case 'c':
    return 0x1a;
  case 'C':
    return 0x9c;
  case 'D':
    return 0x7a;  //
  case 'd':
    return 0x7a;
  case 'e':
    return 0xde;
  case 'E':
    return 0x9e;
  case 'F':
    return 0x8e;
  case 'f':
    return 0x8e;  //
  case 'G':
    return 0xf6;  //
  case 'g':
    return 0xf6;
  case 'H':
    return 0x6e;
  case 'h':
    return 0x2e;
  case 'I':
    return 0x60;
  case 'i':
    return 0x08;
  case 'J':
    return 0x78;
  case 'j':
    return 0x70;
  case 'L':
    return 0x1c;
  case 'l':
    return 0x0c;
  case 'N':
    return 0xec;
  case 'n':
    return 0x2a;
  case 'O':
    return 0x3a;  //
  case 'o':
    return 0x3a;
  case 'P':
    return 0xce;
  case 'p':
    return 0xce;  //
  case 'Q':
    return 0xe6;  //
  case 'q':
    return 0xe6;
  case 'R':
    return 0x0a;  //
  case 'r':
    return 0x0a;
  case 'S':
    return 0xb6;
  case 's':
    return 0xb6;  //
  case 'T':
    return 0x1e;  //
  case 't':
    return 0x1e;
  case 'U':
    return 0x7c;
  case 'u':
    return 0x38;
  case 'Y':
    return 0x76;  //
  case 'y':
    return 0x76;
  case '-':
    return 0x02;
  case '?':
    return 0xcb;
  case '=':
    return 0x12;
  case '"':
    return 0x44;
  default :
    return 0x00;
  }
}

long SevenSegment::Pow10(int p) {
switch (p) {
   case 0: return 1;
   case 1: return 10;
   case 2: return 100;
   case 3: return 1000;
   case 4: return 10000;
   case 5: return 100000;
   case 6: return 1000000;
   case 7: return 10000000;
   case 8: return 100000000;
   case 9: return 1000000000;
   }
return 1;
}
