#!/bin/bash
RUN=/data/share/mouls/XenotransFormer/biomni_run; V=$RUN/venv/bin/python
rm -f $RUN/benchmark.DONE
echo "=== prep targets ==="; $V $RUN/prep_targets.py 2>&1 | tail -6
for T in SC0926 SC0924; do
  for REP in 1 2 3; do
    echo "=== RUN $T rep$REP $(date +%H:%M:%S) ==="
    BIOMNI_ENVFILE=$RUN/.env BIOMNI_MODEL=MiniMax-M3 BIOMNI_TARGET=$T BIOMNI_REP=$REP \
      $V -u $RUN/run_biomni.py > $RUN/run_${T}_rep${REP}.log 2>&1
    calls=$(grep -c "LLM CALL" $RUN/run_${T}_rep${REP}.log)
    wrote=$([ -f $RUN/workspace/${T}_rep${REP}/biomni_labels.csv ] && echo YES || echo NO)
    echo "   $T rep$REP: calls=$calls wrote=$wrote"
  done
done
echo "=== SCORE ==="; $V $RUN/score_all.py 2>&1
echo EXIT=$? > $RUN/benchmark.DONE
