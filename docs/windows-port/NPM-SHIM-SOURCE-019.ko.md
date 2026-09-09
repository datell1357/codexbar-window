# npm shim 고정 근거

shim_source_019가 GitHub API로 확인한 npm/cmd-shim v9.0.2 기준 commit: 7667c245e7d9259b5f88b77fb71b497ffcc26976.
https://github.com/npm/cmd-shim/blob/7667c245e7d9259b5f88b77fb71b497ffcc26976/lib/index.js
https://github.com/npm/cmd-shim/blob/7667c245e7d9259b5f88b77fb71b497ffcc26976/tap-snapshots/test/basic.js.test.cjs

보고된 no-args node shebang template은 dp0 보조 label/SETLOCAL/CALL, sibling node.exe IF EXIST, 없으면 _prog=node, endLocal/goto/title/PATHEXT 치환/target JS/%*를 포함한다. PATHEXT의 ;.JS; 제거가 child 환경에 영향을 준다. shebang env assignment와 node arguments도 generator가 허용하므로 단순 마지막 행에서 JS path만 추출해 모든 shim을 지원했다고 보지 않는다.

다음 담당은 이 pinned raw source/snapshot을 다시 읽어 정확한 문법과 환경 side effect를 확인하고 no-args/no-env template만 처음 인식한다. 현재 문서는 연구 요약이며 generator를 실행하거나 인식기를 검증한 증거가 아니다.
