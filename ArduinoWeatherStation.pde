#include <string.h> //needed for strlen()
#include <OneWire.h>

/* DS18S20 Temperature chip i/o
 */

OneWire  ds(9);  // on pin 9
boolean error;
boolean found;
int Whole, Fract;
int Negative;

byte data[12];
byte addr[8];

// define spi bus pins
#define SLAVESELECT 10
#define SPICLOCK 13
#define DATAOUT 11	//MOSI
#define DATAIN 12	 //MISO
#define UBLB(a,b)  ( ( (a) << 8) | (b) )
#define UBLB19(a,b) ( ( (a) << 16 ) | (b) )

//Addresses
#define REVID 0x00	//ASIC Revision Number
#define OPSTATUS 0x04   //Operation Status
#define STATUS 0x07     //ASIC Status
#define START 0x0A      //Constant Readings
#define PRESSURE 0x1F   //Pressure 3 MSB
#define PRESSURE_LSB 0x20 //Pressure 16 LSB
#define TEMP 0x21       //16 bit temp

byte CurrentDisplayPage = 0;

//Pressure sensor
char rev_in_byte;	    
int temp_in;
unsigned long pressure_lsb;
unsigned long pressure_msb;
unsigned long temp_pressure;
unsigned long pressure;

float Calculation_temp;
int Calculation_temp1;

//Wind vane
const float table[16] = {3.84, 1.98, 2.25, 0.41, 0.45, 0.32, 0.90, 0.62, 1.40, 1.19, 3.08, 2.93, 4.62, 4.32, 4.78, 3.43}; //charecter 13 is not correct, but is changed due to failure in windvane
float voltage;
int angle;
float OldTime;

unsigned long WindReading;
float WindChill;
char buffer[20];

//Anometer
volatile unsigned int windRotation = 0;
//Used for timing
float windTimer = 0;
float windDtime = 0;

//Rain gauge
float RainMeasurement = 0;
unsigned long LastRainReset = 0;
volatile byte Hit = 1;

void setup()
{
  Serial.begin(115200);  
  delay(2000);
  LCD_SetBacklight(100);
  LCD_Clear();
  LCD_CenterText("Initialiserer...", 0);
  DS18B20_Init();
  SCP1000_Init();  
  Vind_Init();
  Rain_Init();
  delay(1000);
  LCD_Clear();
}

void loop() {
  switch (CurrentDisplayPage) {
    case 0:
      if (!error) { Negative = DS18B20_GetTemperature(); }      
      LCD_Clear();
      LCD_CenterText("Vejrstation", 2);
      LCD_CenterText("Temperatur", 11); 
      LCD_DrawBox(26, 0, 100, 20);            
       
      LCD_SetPos(38, 24);
      if (!error)// If the DS18B20 is initialized and found properly 
      {         
        if (!Negative) {
          Calculation_temp = (float)Whole + ((float)(Fract)/100);
          Calculation_temp1 = (Calculation_temp - (int)Calculation_temp) * 100;
          sprintf(buffer, "%0d.%d C", (int)Calculation_temp, Calculation_temp1);
          if ((!Negative && Whole < 25 && WindReading > 2 && WindReading < 22) || (Negative && Whole < 50 && WindReading > 2 && WindReading < 22)) {
            LCD_CenterText(buffer, 28);    
          } else {
            LCD_CenterText(buffer, 38);    
          }
        } else {
          Calculation_temp = (float)Whole + ((float)(Fract)/100);
          Calculation_temp1 = (Calculation_temp - (int)Calculation_temp) * 100;
          sprintf(buffer, "-%0d.%d C", (int)Calculation_temp, Calculation_temp1);
          if ((!Negative && Whole < 25 && WindReading > 2 && WindReading < 22) || (Negative && Whole < 50 && WindReading > 2 && WindReading < 22)) {
            LCD_CenterText(buffer, 28);    
          } else {
            LCD_CenterText(buffer, 38);    
          }  
        }
        if ((!Negative && Whole < 25 && WindReading > 2 && WindReading < 22) || (Negative && Whole < 50 && WindReading > 2 && WindReading < 22)) {
          LCD_CenterText("Chill Factor:", 42);
          WindChill = 0.045*(5.2735*sqrt(WindReading*3.6)+10.45-0.2778*WindReading*3.6)*(Calculation_temp-33.0)+33; //http://www.dmi.dk/dmi/faq_temperatur
    
          Calculation_temp1 = (WindChill - (int)WindChill) * 100;
          sprintf(buffer, "%0d.%d C", (int)WindChill, Calculation_temp1);
          LCD_CenterText(buffer, 52); 
        }      
      } else {
        LCD_CenterText("FEJL:", 28);        
        LCD_CenterText("Tjek forbindelsen",37);
        LCD_CenterText("til sensoren",46);
      }      
      delay(5000);
      break; 
    case 1:
      rev_in_byte = read_register(REVID);
    
      pressure_msb = read_register(PRESSURE);
      pressure_msb &= B00000111;
      pressure_lsb = read_register16(PRESSURE_LSB);
      pressure = UBLB19(pressure_msb, pressure_lsb);
      pressure /= 4;
      LCD_Clear();
      LCD_CenterText("Vejrstation", 2);   
 
      LCD_CenterText("Tryk", 11);
      Serial.print(" ");
      LCD_DrawBox(26, 0, 100, 20);    
      
      Calculation_temp = (float)pressure;               
      sprintf(buffer, "%ld Pa", pressure);
      LCD_CenterText(buffer, 32);    
    
    
      Calculation_temp = (float)pressure/100;
      Calculation_temp1 = (Calculation_temp - (int)Calculation_temp) * 1000;
      sprintf(buffer, "%0d.%0.3d hPa", (int)Calculation_temp, Calculation_temp1);
      LCD_CenterText(buffer, 40);       
      
      
      Calculation_temp = (float)pressure/100000;
      Calculation_temp1 = (Calculation_temp - (int)Calculation_temp) * 100;
      sprintf(buffer, "%0d.%0.2d Bar", (int)Calculation_temp, Calculation_temp1);
      LCD_CenterText(buffer, 48);                
      delay(5000);
      break;    
      
    case 2:
      WindReading = Vind_GetHastighed();
      LCD_Clear();
      LCD_CenterText("Vejrstation", 2);      
      LCD_CenterText("Vind", 11);
      Serial.print(" ");
      LCD_DrawBox(26, 0, 100, 20);    
       
      LCD_CenterText("Retning:", 26);
      Print_VindRetning(36);     
      sprintf(buffer, "Hastighed: %d m/s ", WindReading);
      LCD_CenterText(buffer, 50);
      
      OldTime = millis();
      
      while(millis() < OldTime+5000)
      {
        Print_VindRetning(36);        
        delay(100);
      }
      break;   

    case 3:
      if (LastRainReset+86400000 < millis()) { // LastRainReset > 24 timer
        RainMeasurement = 0;
        LastRainReset = millis();
      }
      LCD_Clear();
      LCD_CenterText("Vejrstation", 2);       
      
      LCD_CenterText("Regn", 11);
      Serial.print(" ");
      LCD_DrawBox(26, 0, 100, 20);                       
    
      Calculation_temp = (float)RainMeasurement;
      Calculation_temp1 = (Calculation_temp - (int)Calculation_temp) * 100;
      sprintf(buffer, "%0d.%d mm", (int)Calculation_temp, Calculation_temp1);
      LCD_CenterText(buffer, 36);       
      delay(5000);
      break;
  }
  CurrentDisplayPage++;
  if (CurrentDisplayPage == 4) {
    CurrentDisplayPage = 0;
  }
} 

void DS18B20_Init(void)
{
  error = false;
  found = false;
  ds.reset_search();
  while (ds.search(addr)) {
    if (OneWire::crc8( addr, 7) != addr[7]) {
      //LCD_SetPos(0,14);
      //Serial.print("CRC is not valid!"); 
      LCD_CenterText("* Temperatur: FEJL", 14);
    }
    if ( addr[0] != 0x28) {
      //LCD_SetPos(0,14);
      //Serial.print("Device is not a DS18B20 family device.");
      LCD_CenterText("* Temperatur: FEJL", 14);
    } else {
      LCD_CenterText("* Temperatur", 14);
      found = true;      
      break;
    }
  }
  
  if (!ds.search(addr) && !found) {  
    //LCD_SetPos(0,14);
    //Serial.print("There wasn't found any DS18B20 device on the OneWire line.");
    LCD_CenterText("* Temperatur: FEJL", 14);    
    error = true;
  }  
}  

int DS18B20_GetTemperature(void) {
  int HighByte, LowByte, TReading, Tc_100, SignBit; 
  byte i;

  ds.reset();
  ds.select(addr);
  ds.write(0x44,1);         // start conversion, with parasite power on at the end
  
  delay(1000);     // maybe 750ms is enough, maybe not
  // we might do a ds.depower() here, but the reset will take care of it.
  
  ds.reset();
  ds.select(addr);    
  ds.write(0xBE);         // Read Scratchpad

  for ( i = 0; i < 9; i++) {           // we need 9 bytes
    data[i] = ds.read();
  }
  if (OneWire::crc8( data, 8) == data[8]) {
    LowByte = data[0];
    HighByte = data[1];
    TReading = (HighByte << 8) + LowByte;
    SignBit = TReading & 0x8000;  // test most sig bit
    if (SignBit) // negative
    {
      TReading = (TReading ^ 0xffff) + 1; // 2's comp
    }
    Tc_100 = (6 * TReading) + TReading / 4;    // multiply by (100 * 0.0625) or 6.25 - 12-bit presission (DS18B20)
    //Tc_100 = 50 * TReading;    // multiply by (100 * 0.5) or 50 (DS18S20)
  
    Whole = Tc_100 / 100;  // separate off the whole and fractional portions
    Fract = Tc_100 % 100;
  
    return SignBit;
  }
}  

void SCP1000_Init(void)
{
  byte clr;
  pinMode(DATAOUT, OUTPUT);
  pinMode(DATAIN, INPUT);
  pinMode(SPICLOCK,OUTPUT);
  pinMode(SLAVESELECT,OUTPUT);
  digitalWrite(SLAVESELECT,HIGH); //disable device  
  
  SPCR = B01010011; //MPIE=0, SPE=1 (on), DORD=0 (MSB first), MSTR=1 (master), CPOL=0 (clock idle when low), CPHA=0 (samples MOSI on rising edge), SPR1=0 & SPR0=0 (500kHz)
  clr=SPSR;
  clr=SPDR;
  delay(10);

  LCD_CenterText("* Tryk", 24);
  write_register(0x03,0x09);
}  

void SCP1000_GetTemperature(void)
{
  temp_in = read_register16(TEMP);
  temp_in = temp_in / 20;
}

char spi_transfer(volatile char data)
{
  SPDR = data;			  // Start the transmission
  while (!(SPSR & (1<<SPIF)))     // Wait for the end of the transmission
  {
  };
  return SPDR;			  // return the received byte
}


char read_register(char register_name)
{
    char in_byte;
    register_name <<= 2;
    register_name &= B11111100; //Read command
  
    digitalWrite(SLAVESELECT,LOW); //Select SPI Device
    spi_transfer(register_name); //Write byte to device
    in_byte = spi_transfer(0x00); //Send nothing, but we should get back the register value
    digitalWrite(SLAVESELECT,HIGH);
    delay(10);
    return(in_byte);
  
}

float read_register16(char register_name)
{
    byte in_byte1;
    byte in_byte2;
    float in_word;
    
    register_name <<= 2;
    register_name &= B11111100; //Read command

    digitalWrite(SLAVESELECT,LOW); //Select SPI Device
    spi_transfer(register_name); //Write byte to device
    in_byte1 = spi_transfer(0x00);    
    in_byte2 = spi_transfer(0x00);
    digitalWrite(SLAVESELECT,HIGH);
    in_word = UBLB(in_byte1,in_byte2);
    return(in_word);
}

void write_register(char register_name, char register_value)
{
    register_name <<= 2;
    register_name |= B00000010; //Write command

    digitalWrite(SLAVESELECT,LOW); //Select SPI device
    spi_transfer(register_name); //Send register location
    spi_transfer(register_value); //Send value to record into register
    digitalWrite(SLAVESELECT,HIGH);
}


void Vind_Init(void)
{
  pinMode(3, INPUT);
  attachInterrupt(1, windSpeed, RISING);
  windTimer=millis();//start timing  
  LCD_CenterText("* Vind Retning", 34);
  LCD_CenterText("* Vind Hastighed", 44);
}

void Print_VindRetning(byte y)
{
    // read the analog input into a variable:
   voltage = analogRead(0)/204.6;   
   for (int i = 0; i < 16; i++) {
     if (voltage <= table[i]+0.03 && voltage >= table[i]-0.03) {
       angle = i;
       break;
     }
   } 
   //Serial.println(angle, DEC);//print the result
   LCD_EraseBlock(0, y-10, 127, y+10);
   switch (angle) {
     case 0:
       LCD_CenterText("Nord", y);
       break;
     case 1:
       LCD_CenterText("Nord", y); // Nord Nordøst
       break;       
     case 2:
       LCD_CenterText("Nord 0st", y);
       break;       
     case 3:
       LCD_CenterText("0st", y);
       break;       
     case 4:
       LCD_CenterText("0st", y);
       break;       
     case 5:
       LCD_CenterText("0st", y);
       break;       
     case 6:
       LCD_CenterText("Syd 0st", y);   
       break;       
     case 7:
       LCD_CenterText("Syd", y); // Syd Sydøst
       break;       
     case 8:
       LCD_CenterText("Syd", y);      
       break;       
     case 9:
       LCD_CenterText("Syd", y); // Syd Sydvest 
       break;       
     case 10:
       LCD_CenterText("Syd Vest", y);     
       break;       
     case 11:
       LCD_CenterText("Vest", y); // Vest Sydvest
       break;       
     case 12:
       LCD_CenterText("Vest", y);        
       break;       
     case 13:
       LCD_CenterText("Nord Vest", y); // Vest Nordvest  - the windvane is not precise         
       break;       
     case 14:
       LCD_CenterText("Nord Vest", y);                       
       break;       
     case 15:
       LCD_CenterText("Nord", y);  // Nord Nordvest                     
       break;        
     default:
       break;
   }  
}  

int Vind_GetHastighed(void)
{
  /*
  The cup-type anemometer measures wind speed by closing a contact as 
  a magnet moves past a switch.  A wind speed of 1.492 MPH (2.4 km/h) 
  causes the switch to close once per second.
  */ 
  
  //Check using Interrupt
  float windSpeed = 0;
  
  windDtime =  millis()-windTimer;
  windTimer = millis();
  windDtime = windDtime/1000;
  windSpeed = windRotation/windDtime;//rotation per second
  windRotation = 0;  
  windSpeed = windSpeed*2/3;//1 rotation per second equals 2.4 km/h = 2/3 m/s
  return int(windSpeed); 
}

void windSpeed()
{
  windRotation++;
}

void Rain_Init(void)
{
  attachInterrupt(0, Rain_Measure, RISING);
  LastRainReset = millis();
  LCD_CenterText("* Regn", 54);
}    

void Rain_Measure(void)
{
  if (Hit == 1) {
    Hit = 2;
  } else if (Hit == 2) {
    Hit = 3;
  } else if (Hit == 3) {
    RainMeasurement = RainMeasurement + 0.2794;
    Hit = 1;   
  }  
}

void LCD_Clear(void)
{
  Serial.print(0x7C, BYTE);
  Serial.print(0x00, BYTE); 
}
 
void LCD_DrawBox(byte x1, byte y1, byte x2, byte y2)
{
  Serial.print(0x7C, BYTE);
  Serial.print(0x0F, BYTE);  
  Serial.print(x1, BYTE);    
  Serial.print(y1, BYTE);
  Serial.print(x2, BYTE);    
  Serial.print(y2, BYTE);  
  Serial.print(0x01, BYTE);  
}

void LCD_EraseBlock(byte x1, byte y1, byte x2, byte y2)
{
  Serial.print(0x7C, BYTE);
  Serial.print(0x05, BYTE);  
  Serial.print(x1, BYTE);    
  Serial.print(y1, BYTE);
  Serial.print(x2, BYTE);    
  Serial.print(y2, BYTE);  
}  


void LCD_SetPos(byte x, byte y)
{
  Serial.print(0x7C, BYTE);
  Serial.print(0x18, BYTE);  
  Serial.print(x, BYTE);    
  Serial.print(0x7C, BYTE);
  Serial.print(0x19, BYTE);  
  Serial.print(y, BYTE);  
}

void LCD_CenterText(char text[], byte y)
{
  int textLen = strlen(text);
  if (textLen < 21) {
    LCD_SetPos(64-((textLen*6)/2), y);
    Serial.print(text);
  } else {
    char temp_text[22];
    for (int character = 0; character < 21; character++) {
      temp_text[character] = text[character];
    }
    temp_text[21] = 0;
    LCD_SetPos(64-((strlen(temp_text)*6)/2), y);
    Serial.print(temp_text);
  }
}
  
void LCD_SetBacklight(byte intensity)
{
  if (intensity <= 100) {
    Serial.print(0x7C, BYTE);
    Serial.print(0x02, BYTE);  
    Serial.print(intensity, BYTE);  
  }
} 
