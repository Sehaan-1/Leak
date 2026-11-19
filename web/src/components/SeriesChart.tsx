import { Bar, BarChart, CartesianGrid, Cell, ReferenceLine, Tooltip, XAxis, YAxis } from "recharts";
import type { SeriesCharge } from "../api/client";
import { formatPlainDate } from "../lib/dates";
import { formatRupees, paiseToDecimal } from "../lib/money";
import { formatMonth } from "../lib/series";

const USUAL = "#0b57d0";
const STEP = "#b3261e";

type Point = { date: string; rupees: number; paise: number; step: boolean };

/**
 * Each charge as a bar, the first charge at a new price in red with a
 * labelled line. Decorative for assistive technology: the charges table on
 * the same screen carries the same data, so the chart is hidden from it
 * (and its keyboard layer is off).
 */
export default function SeriesChart({ charges }: { charges: SeriesCharge[] }) {
  // Recharts needs plain numbers to scale bars; labels still use paise.
  const data: Point[] = charges.map((c) => ({
    date: c.posted_on,
    rupees: Number(paiseToDecimal(c.charged_paise)),
    paise: c.charged_paise,
    step: c.price_step,
  }));
  const step = data.find((point) => point.step);

  return (
    <div className="chart" aria-hidden="true">
      <BarChart
        responsive
        style={{ inlineSize: "100%", blockSize: "100%" }}
        data={data}
        accessibilityLayer={false}
        margin={{ top: 28, right: 12, bottom: 4, left: 8 }}
      >
        <CartesianGrid vertical={false} stroke="#e0e0e0" />
        <XAxis dataKey="date" tickFormatter={(iso: string) => formatMonth(iso)} minTickGap={24} />
        <YAxis
          width={72}
          tickFormatter={(rupees: number) => formatRupees(Math.round(rupees * 100)).replace(/\.00$/, "")}
        />
        <Tooltip
          formatter={(_value, _name, item) => [formatRupees((item.payload as Point).paise), "Charged"]}
          labelFormatter={(iso) => formatPlainDate(String(iso))}
        />
        {step && (
          <ReferenceLine
            x={step.date}
            stroke={STEP}
            strokeDasharray="4 4"
            label={{ value: "Price went up", position: "top", fill: STEP, fontWeight: 600 }}
          />
        )}
        <Bar dataKey="rupees" isAnimationActive={false}>
          {data.map((point) => (
            <Cell key={point.date} fill={point.step ? STEP : USUAL} />
          ))}
        </Bar>
      </BarChart>
    </div>
  );
}
