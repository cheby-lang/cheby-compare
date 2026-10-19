// word_freq: counts the words of a file and prints the 20 most frequent.

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class Main {
    private static final int TOP = 20;

    public static void main(String[] args) throws IOException {
        String text = Files.readString(Path.of(args[0]), StandardCharsets.US_ASCII);

        Map<String, Integer> counts = new HashMap<>();
        long total = 0;
        for (String word : text.split("\\s+")) {
            if (word.isEmpty()) {
                continue; // only a leading empty part, or the one part of an empty file
            }
            counts.merge(word, 1, Integer::sum);
            total++;
        }

        List<Map.Entry<String, Integer>> ranked = new ArrayList<>(counts.entrySet());
        ranked.sort((a, b) -> {
            int byCount = Integer.compare(b.getValue(), a.getValue());
            return byCount != 0 ? byCount : a.getKey().compareTo(b.getKey());
        });

        StringBuilder out = new StringBuilder();
        out.append("total ").append(total).append('\n');
        out.append("distinct ").append(counts.size()).append('\n');
        for (Map.Entry<String, Integer> e : ranked.subList(0, Math.min(TOP, ranked.size()))) {
            out.append(e.getValue()).append(' ').append(e.getKey()).append('\n');
        }
        System.out.print(out);
    }
}
