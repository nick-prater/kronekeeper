Attribute VB_Name = "Module1"
Private Sub Main()

' MIT License
'
' Copyright (c) 2016 NP Broadcast Limited
'
' Permission is hereby granted, free of charge, to any person obtaining a copy
' of this software and associated documentation files (the "Software"), to deal
' in the Software without restriction, including without limitation the rights
' to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
' copies of the Software, and to permit persons to whom the Software is
' furnished to do so, subject to the following conditions:
' 
' The above copyright notice and this permission notice shall be included in all
' copies or substantial portions of the Software.
' 
' THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
' IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
' FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
' AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
' LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
' OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
' SOFTWARE.

Dim db As Database
Dim dbPath As String
Dim outputDir As String
Dim tables, t As Variant

dbPath = Command()
outputDir = CurDir()
tables = Array( _
    "Blocks", _
    "CCTLU", _
    "Circuits", _
    "Info", _
    "Jumper Groups", _
    "Jumpers", _
    "OldJumpers", _
    "PrintInf", _
    "PrintIssue", _
    "Stack" _
)

Set db = OpenDatabase(dbPath)
For Each t In tables
    db.Execute ( _
        "SELECT * INTO [Text;HDR=No;DATABASE=" _
        & outputDir _
        & "].[" _
        & t _
        & ".csv] FROM [" _
        & t _
        & "]" _
    )
Next t

db.Close
End Sub

