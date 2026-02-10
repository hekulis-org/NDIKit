# Third-Party Notices

This file documents third-party licensing and attribution requirements for
software built with or distributed alongside NDIKit.

## Scope

- NDIKit-authored code is licensed under MIT. See `NDIKit/LICENSE`.
- Third-party SDK files from Vizrt NDI AB are not relicensed by NDIKit and
  remain under their upstream terms.

## NDI SDK (Vizrt NDI AB)

NDIKit wraps and redistributes components from the official NDI SDK.

- Copyright (C) 2023-2025 Vizrt NDI AB.
- All rights reserved, except where specific SDK files state otherwise.

Use and redistribution are governed by the NDI SDK License Agreement:

- `NDI License Agreement.pdf` provided with the upstream SDK
- https://docs.ndi.video/all/developing-with-ndi/sdk/licensing
- http://ndi.link/ndisdk_license

## Required Attribution

Include the following attribution in your app/legal notices when distributing
software that uses NDI technology:

`This product includes NDI(R) technology licensed from Vizrt NDI AB.`

Trademark notice:

`NDI(R) is a registered trademark of Vizrt NDI AB.`

## MIT-Licensed NDI SDK Header Files

The following NDI SDK headers state that MIT terms apply to those files only:

- `Processing.NDI.Lib.cplusplus.h`
- `Processing.NDI.utilities.h`

When redistributing copies or substantial portions of those files, include this
notice:

```text
Copyright (C) 2023-2025 Vizrt NDI AB.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The MIT terms above apply only to those specific headers. All other NDI SDK
components remain under the NDI SDK license agreement.
