// json_roundtrip: parses a JSON array of records, transforms it and serializes it again.
//
// Jackson 3 databind with records: the input decodes into InputRecord, and each kept record is a new
// Output, which Jackson writes in component order. Address and Entry are records too, so their
// key order is fixed and they are shared between input and output.

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

public class Main {
    private static final long FNV_OFFSET = 2_166_136_261L;
    private static final long FNV_PRIME = 16_777_619L;

    record Address(String street, String city, long zip) {}

    record Entry(long day, long amount) {}

    record InputRecord(long id, String name, boolean active, long score, List<String> tags,
            Address address, List<Entry> history) {}

    /** A kept record as it is written: active is gone, score changed and total added. */
    record Output(long id, String name, long score, List<String> tags, Address address,
            List<Entry> history, long total) {}

    private static final TypeReference<List<InputRecord>> RECORDS = new TypeReference<>() {};

    private static long fnv1a(long hash, byte[] data) {
        long h = hash;
        for (byte b : data) {
            h = ((h ^ (b & 0xFF)) * FNV_PRIME) & 0xFFFFFFFFL;
        }
        return h;
    }

    public static void main(String[] args) throws IOException {
        String text = Files.readString(Path.of(args[0]), StandardCharsets.US_ASCII);
        long reps = Long.parseLong(args[1]);
        ObjectMapper mapper = JsonMapper.builder().build();

        long recordsN = 0, activeN = 0, scoreSum = 0, tagsN = 0;
        long historyN = 0, amountSum = 0, outputBytes = 0;
        long hash = FNV_OFFSET;
        for (long rep = 0; rep < reps; rep++) {
            List<InputRecord> records = mapper.readValue(text, RECORDS);
            List<Output> kept = new ArrayList<>();
            for (InputRecord r : records) {
                long total = 0;
                for (Entry e : r.history()) {
                    total += e.amount();
                }
                recordsN++;
                scoreSum += r.score();
                tagsN += r.tags().size();
                historyN += r.history().size();
                amountSum += total;
                if (r.active()) {
                    activeN++;
                    kept.add(new Output(r.id(), r.name(), r.score() + 100L * r.tags().size(),
                            r.tags(), r.address(), r.history(), total));
                }
            }
            byte[] out = mapper.writeValueAsBytes(kept);
            outputBytes += out.length;
            if (rep == reps - 1) {
                hash = fnv1a(FNV_OFFSET, out);
            }
        }

        System.out.print("records " + recordsN + "\nactive " + activeN + "\nscore_sum " + scoreSum
                + "\ntags " + tagsN + "\nhistory " + historyN + "\namount_sum " + amountSum
                + "\noutput_bytes " + outputBytes + "\noutput_fnv1a " + hash + "\n");
    }
}
