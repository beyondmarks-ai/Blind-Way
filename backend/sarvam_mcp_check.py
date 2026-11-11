"""Inspect and exercise the user's official Sarvam MCP server without logging keys."""
import asyncio
import json
import os
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def main():
    command = os.environ.get('SARVAM_UVX', 'uvx')
    async with stdio_client(StdioServerParameters(command=command, args=['sarvam-mcp'], env=dict(os.environ))) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            await session.initialize()
            if len(sys.argv) > 1 and sys.argv[1] == '--smoke':
                for code, text in [('hi-IN','मेरे सामने क्या है?'), ('ta-IN','எனக்கு முன்னால் என்ன இருக்கிறது?'), ('en-IN','Hey Jarvis')]:
                    spoken = await session.call_tool('sarvam_tools_tts_speak', {'text':text,'target_language_code':code,'speaker':'ritu','model':'bulbul:v3','speech_sample_rate':16000})
                    if spoken.is_error:
                        raise RuntimeError(spoken.model_dump_json())
                    speech = spoken.structured_content
                    heard = await session.call_tool('sarvam_tools_stt_transcribe', {'audio_path':speech['file_path'],'language_code':'unknown','model':'saaras:v4','mode':'transcribe'})
                    print(json.dumps({'requested':code,'audio':speech,'recognized':heard.structured_content,'error':heard.is_error},ensure_ascii=True),flush=True)
            elif len(sys.argv) > 1:
                args = json.load(open(sys.argv[2][1:], encoding='utf-8-sig')) if sys.argv[2].startswith('@') else json.loads(sys.argv[2])
                response = await session.call_tool(sys.argv[1], args)
                print(json.dumps(response.model_dump(mode='json'),ensure_ascii=True))
            else:
                result = await session.list_tools()
                for tool in result.tools:
                    if any(word in tool.name for word in ['languages', 'recommend', 'tts_speak', 'stt_transcribe', 'api_reference']):
                        print(json.dumps({'name': tool.name, 'schema': tool.input_schema}))

asyncio.run(main())
